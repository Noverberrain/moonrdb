// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
priv struct DecodeBudget {
  limit : Int32
  mut used : Int32
}

///|
priv struct DecodedString {
  value : Bytes
  storage : StringStorage
}

///|
fn DecodeBudget::charge(
  self : DecodeBudget,
  count : UInt64,
  offset : Int32,
) -> Unit raise ParseError {
  check_resource_limit(
    "decoded-bytes",
    offset,
    self.used.to_uint64() + count,
    self.limit,
  )
  self.used += count.to_int()
}

///|
fn Reader::read_string(
  self : Reader,
  max_string_bytes : Int32,
  budget : DecodeBudget,
  allow_lzf~ : Bool,
  resource~ : String,
) -> DecodedString raise ParseError {
  let offset = self.pos
  let initial_used = budget.used
  errdefer {
    self.pos = offset
    budget.used = initial_used
  }
  let (value, storage) = match self.read_length() {
    Plain(count) => {
      check_resource_limit(resource, offset, count, max_string_bytes)
      self.require(count)
      budget.charge(count, offset)
      (self.read_bytes(count).to_owned(), Raw)
    }
    Encoded(Int8) => (b"\{self.read_i8()}", Integer8)
    Encoded(Int16) => (b"\{self.read_i16_le()}", Integer16)
    Encoded(Int32) => (b"\{self.read_i32_le()}", Integer32)
    Encoded(Lzf) => {
      if !allow_lzf {
        raise UnsupportedStringEncoding(offset~, encoding=3)
      }
      let compressed_size = self.read_count()
      let output_size = self.read_count()
      check_resource_limit(resource, offset, output_size, max_string_bytes)
      self.require(compressed_size)
      budget.charge(output_size, offset)
      let base_offset = self.pos
      let payload = self.read_bytes(compressed_size)
      (decompress_lzf(payload, output_size.to_int(), base_offset), Lzf)
    }
  }
  if storage is (Integer8 | Integer16 | Integer32) {
    check_resource_limit(
      resource,
      offset,
      value.length().to_uint64(),
      max_string_bytes,
    )
    budget.charge(value.length().to_uint64(), offset)
  }
  { value, storage, }
}

///|
fn Reader::read_string_record(
  self : Reader,
  prefix : KeyPrefix,
  database : UInt64,
  max_string_bytes : Int32,
  budget : DecodeBudget,
) -> StringRecord raise ParseError {
  let key = self.read_string(
    max_string_bytes,
    budget,
    allow_lzf=true,
    resource="string-bytes",
  )
  let value = self.read_string(
    max_string_bytes,
    budget,
    allow_lzf=true,
    resource="string-bytes",
  )
  {
    database,
    key: key.value,
    value: value.value,
    key_storage: key.storage,
    value_storage: value.storage,
    expires_at_ms: prefix.expires_at_ms,
    idle_seconds: prefix.idle_seconds,
    frequency: prefix.frequency,
    record_start: prefix.start,
    record_end: self.pos,
    serialized_bytes: (self.pos - prefix.start).to_uint64(),
  }
}
