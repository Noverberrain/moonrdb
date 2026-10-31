// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn Reader::read_aux_string(
  self : Reader,
  max_string_bytes : Int32,
) -> Bytes raise ParseError {
  let offset = self.pos
  errdefer {
    self.pos = offset
  }
  let value = match self.read_length() {
    Plain(count) => {
      check_resource_limit("aux-string-bytes", offset, count, max_string_bytes)
      self.read_bytes(count).to_owned()
    }
    Encoded(Int8) => b"\{self.read_i8()}"
    Encoded(Int16) => b"\{self.read_i16_le()}"
    Encoded(Int32) => b"\{self.read_i32_le()}"
    Encoded(Lzf) => raise UnsupportedStringEncoding(offset~, encoding=3)
  }
  check_resource_limit(
    "aux-string-bytes",
    offset,
    value.length().to_uint64(),
    max_string_bytes,
  )
  value
}

///|
fn check_resource_limit(
  resource : String,
  offset : Int32,
  actual : UInt64,
  limit : Int32,
) -> Unit raise ParseError {
  if actual > limit.to_uint64() {
    raise ResourceLimitExceeded(
      offset~,
      resource~,
      actual~,
      limit=limit.to_uint64(),
    )
  }
}
