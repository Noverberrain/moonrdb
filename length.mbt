// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
priv enum StringEncoding {
  Int8
  Int16
  Int32
  Lzf
} derive(Debug, Eq)

///|
// Traits support F1 white-box tests; production consumers arrive with F2/F3.
#warnings("-unused_value")
priv enum Length {
  Plain(UInt64)
  Encoded(StringEncoding)
} derive(Debug, Eq)

///|
// Composite reads restore the cursor on failure, retaining the original error
// offset. No object payload or decompression is performed in F1.
fn Reader::read_length(self : Reader) -> Length raise ParseError {
  let start = self.pos
  errdefer {
    self.pos = start
  }
  self.read_length_inner()
}

///|
fn Reader::read_length_inner(self : Reader) -> Length raise ParseError {
  let offset = self.pos
  let tag = self.read_u8()
  let value = tag.to_int()
  match value >> 6 {
    0 => Plain(value.to_uint64())
    1 => Plain(((value & 0x3f).to_uint64() << 8) | self.read_u8().to_uint64())
    2 =>
      match value {
        0x80 => Plain(self.read_unsigned(4, little_endian=false))
        0x81 => Plain(self.read_unsigned(8, little_endian=false))
        _ => raise InvalidLengthTag(offset~, tag~)
      }
    _ =>
      match value & 0x3f {
        0 => Encoded(Int8)
        1 => Encoded(Int16)
        2 => Encoded(Int32)
        3 => Encoded(Lzf)
        encoding => raise InvalidStringEncoding(offset~, encoding~)
      }
  }
}

///|
// Collection counts and similar contexts cannot use encoded-string markers.
fn Reader::read_count(self : Reader) -> UInt64 raise ParseError {
  let offset = self.pos
  match self.read_length() {
    Plain(value) => value
    Encoded(_) => {
      self.pos = offset
      raise UnexpectedEncodedLength(offset~)
    }
  }
}
