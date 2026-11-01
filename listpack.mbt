// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn listpack_backlen_size(length : UInt64) -> Int32 {
  if length <= 127UL {
    1
  } else if length < 16383UL {
    2
  } else if length < 2097151UL {
    3
  } else if length < 268435455UL {
    4
  } else {
    5
  }
}

///|
// The last byte belongs to the listpack terminator, never an entry payload.
fn Reader::lp_read(
  self : Reader,
  count : UInt64,
  base : Int32,
) -> BytesView raise ParseError {
  let remaining = self.input.length() - 1 - self.pos
  if remaining < 0 || count > remaining.to_uint64() {
    raise InvalidListpack(
      offset=base,
      inner_offset=self.pos,
      reason="truncated entry",
    )
  }
  self.read_bytes(count)
}

///|
fn Reader::lp_unsigned(
  self : Reader,
  width : Int32,
  base : Int32,
) -> UInt64 raise ParseError {
  let bytes = self.lp_read(width.to_uint64(), base)
  for i = width - 1, value = 0UL; i >= 0; i = i - 1 {
    continue i - 1, (value << 8) | bytes[i].to_uint64()
  } nobreak {
    value
  }
}

///|
fn listpack_signed(raw : UInt64, bits : Int32) -> Int64 {
  if bits == 64 {
    raw.reinterpret_as_int64()
  } else if raw >= 1UL << (bits - 1) {
    raw.reinterpret_as_int64() - (1L << bits)
  } else {
    raw.reinterpret_as_int64()
  }
}

///|
fn Reader::lp_string(
  self : Reader,
  count : UInt64,
  base : Int32,
  max_string_bytes : Int32,
  budget : DecodeBudget,
) -> Bytes raise ParseError {
  check_resource_limit("string-bytes", base, count, max_string_bytes)
  let bytes = self.lp_read(count, base)
  budget.charge(count, base)
  bytes.to_owned()
}

///|
fn Reader::read_listpack_entry(
  self : Reader,
  base : Int32,
  max_string_bytes : Int32,
  budget : DecodeBudget,
) -> Bytes raise ParseError {
  let start = self.pos
  let initial_used = budget.used
  errdefer {
    self.pos = start
    budget.used = initial_used
  }
  let tag = self.lp_read(1UL, base)[0].to_int()
  let mut integer = false
  let value = if tag < 128 {
    integer = true
    b"\{tag}"
  } else if tag < 192 {
    self.lp_string((tag & 63).to_uint64(), base, max_string_bytes, budget)
  } else if tag < 224 {
    integer = true
    let raw = ((tag & 31).to_uint64() << 8) | self.lp_unsigned(1, base)
    b"\{listpack_signed(raw, 13)}"
  } else if tag < 240 {
    let count = ((tag & 15).to_uint64() << 8) | self.lp_unsigned(1, base)
    self.lp_string(count, base, max_string_bytes, budget)
  } else if tag == 240 {
    let count = self.lp_unsigned(4, base)
    self.lp_string(count, base, max_string_bytes, budget)
  } else if tag <= 244 {
    integer = true
    let width = match tag {
      241 => 2
      242 => 3
      243 => 4
      _ => 8
    }
    let raw = self.lp_unsigned(width, base)
    b"\{listpack_signed(raw, width * 8)}"
  } else {
    raise InvalidListpack(
      offset=base,
      inner_offset=start,
      reason="unknown entry encoding or premature terminator",
    )
  }
  if integer {
    check_resource_limit(
      "string-bytes",
      base,
      value.length().to_uint64(),
      max_string_bytes,
    )
    budget.charge(value.length().to_uint64(), base)
  }
  let length = (self.pos - start).to_uint64()
  let width = listpack_backlen_size(length)
  let back_start = self.pos
  let bytes = self.lp_read(width.to_uint64(), base)
  for i in 0..<width {
    let part = ((length >> ((width - 1 - i) * 7)) & 127UL).to_int()
    let expected = if i == 0 { part } else { part | 128 }
    if bytes[i].to_int() != expected {
      raise InvalidListpack(
        offset=base,
        inner_offset=back_start + i,
        reason="incorrect entry back length",
      )
    }
  }
  value
}

///|
fn decode_hash_listpack(
  input : Bytes,
  base : Int32,
  max_string_bytes : Int32,
  max_hash_entries : Int32,
  budget : DecodeBudget,
) -> Array[HashEntry] raise ParseError {
  let (reader, declared) = open_listpack(input, base)
  if declared != 65535 {
    if declared % 2 != 0 {
      raise InvalidHash(offset=base, reason="odd listpack element count")
    }
    check_resource_limit(
      "hash-entries",
      base,
      (declared / 2).to_uint64(),
      max_hash_entries,
    )
  }
  let entries = []
  let seen : Map[Bytes, Unit] = Map([])
  while reader.pos < input.length() - 1 {
    check_resource_limit(
      "hash-entries",
      base,
      entries.length().to_uint64() + 1UL,
      max_hash_entries,
    )
    let field = reader.read_listpack_entry(base, max_string_bytes, budget)
    if reader.pos == input.length() - 1 {
      raise InvalidHash(offset=base, reason="odd listpack element count")
    }
    if seen.contains(field) {
      raise InvalidHash(offset=base, reason="duplicate field")
    }
    seen[field] = ()
    let value = reader.read_listpack_entry(base, max_string_bytes, budget)
    entries.push({ field, value, })
  }
  if declared != 65535 &&
    declared.to_uint64() != entries.length().to_uint64() * 2UL {
    raise InvalidListpack(
      offset=base,
      inner_offset=4,
      reason="element count mismatch",
    )
  }
  if entries.is_empty() {
    raise InvalidHash(offset=base, reason="empty hash")
  }
  entries
}

///|
fn open_listpack(
  input : Bytes,
  base : Int32,
) -> (Reader, Int32) raise ParseError {
  if input.length() < 7 {
    raise InvalidListpack(
      offset=base,
      inner_offset=0,
      reason="short header or missing terminator",
    )
  }
  let reader = Reader::new(input, max_input_bytes=input.length())
  let total = reader.read_u32_le()
  if total != input.length().reinterpret_as_uint() {
    raise InvalidListpack(
      offset=base,
      inner_offset=0,
      reason="total length mismatch",
    )
  }
  let declared = reader.read_unsigned(2, little_endian=true).to_int()
  if input[input.length() - 1] != b'\xff' {
    raise InvalidListpack(
      offset=base,
      inner_offset=input.length() - 1,
      reason="missing terminator",
    )
  }
  (reader, declared)
}
