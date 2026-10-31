// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
priv struct Reader {
  input : Bytes
  mut pos : Int32
}

///|
fn Reader::new(
  input : Bytes,
  max_input_bytes~ : Int32,
) -> Reader raise ParseError {
  if max_input_bytes < 0 {
    raise InvalidInputLimit(offset=0, limit=max_input_bytes)
  }
  if input.length() > max_input_bytes {
    raise InputTooLarge(offset=0, size=input.length(), limit=max_input_bytes)
  }
  { input, pos: 0, }
}

///|
fn Reader::remaining(self : Reader) -> Int32 {
  self.input.length() - self.pos
}

///|
fn Reader::require(self : Reader, count : UInt64) -> Unit raise ParseError {
  let remaining = self.remaining()
  if count > remaining.to_uint64() {
    raise UnexpectedEnd(offset=self.pos, needed=count, remaining~)
  }
}

///|
// Check before narrowing or adding. The returned view does not copy data.
fn Reader::read_bytes(
  self : Reader,
  count : UInt64,
) -> BytesView raise ParseError {
  self.require(count)
  let start = self.pos
  self.pos += count.to_int()
  self.input[start:self.pos]
}

///|
fn Reader::read_u8(self : Reader) -> Byte raise ParseError {
  self.read_bytes(1UL)[0]
}

///|
// All callers use fixed widths 1, 2, 4 or 8, so shifts remain within 0..63.
fn Reader::read_unsigned(
  self : Reader,
  width : Int32,
  little_endian~ : Bool,
) -> UInt64 raise ParseError {
  let bytes = self.read_bytes(width.to_uint64())
  for i = 0, value = 0UL; i < width; i = i + 1 {
    let index = if little_endian { width - 1 - i } else { i }
    continue i + 1, (value << 8) | bytes[index].to_uint64()
  } nobreak {
    value
  }
}

///|
fn Reader::read_u32_le(self : Reader) -> UInt32 raise ParseError {
  self.read_unsigned(4, little_endian=true).to_uint()
}

///|
fn Reader::read_u64_le(self : Reader) -> UInt64 raise ParseError {
  self.read_unsigned(8, little_endian=true)
}

///|
fn Reader::read_i8(self : Reader) -> Int32 raise ParseError {
  let raw = self.read_u8().to_int()
  if raw >= 128 {
    raw - 256
  } else {
    raw
  }
}

///|
fn Reader::read_i16_le(self : Reader) -> Int32 raise ParseError {
  let raw = self.read_unsigned(2, little_endian=true).to_int()
  if raw >= 32768 {
    raw - 65536
  } else {
    raw
  }
}

///|
fn Reader::read_i32_le(self : Reader) -> Int32 raise ParseError {
  self.read_u32_le().reinterpret_as_int()
}

///|
fn Reader::read_i64_le(self : Reader) -> Int64 raise ParseError {
  self.read_u64_le().reinterpret_as_int64()
}

///|
fn Reader::read_header(self : Reader) -> Int32 raise ParseError {
  self.require(9UL)
  let start = self.pos
  let magic = b"REDIS"
  for i in 0..<5 {
    if self.input[start + i] != magic[i] {
      raise InvalidMagic(offset=start + i)
    }
  }
  let mut version = 0
  for i in 5..<9 {
    let digit = self.input[start + i].to_int()
    if digit < 48 || digit > 57 {
      raise InvalidVersionDigit(offset=start + i)
    }
    version = version * 10 + digit - 48
  }
  if version != 11 {
    raise UnsupportedVersion(offset=start + 5, version~)
  }
  self.pos = start + 9
  version
}
