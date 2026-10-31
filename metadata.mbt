// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
// F2 tests retain these values; object decoding will consume them in F3.
#warnings("-unused_field")
priv struct KeyPrefix {
  start : Int32
  type_offset : Int32
  object_type : Byte
  expires_at_ms : Int64?
  idle_seconds : UInt64?
  frequency : Byte?
}

///|
fn is_object_type(value : Byte) -> Bool {
  let value = value.to_int()
  (value >= 0 && value <= 7) || (value >= 9 && value <= 21)
}

///|
// Called after the first metadata opcode. No clock or expiry filtering is used.
// Unknown encodings are never skipped. Subsequent record parsing arrives in F3.
fn Reader::read_key_prefix(
  self : Reader,
  first : Byte,
  start : Int32,
) -> KeyPrefix raise ParseError {
  let entry_pos = self.pos
  errdefer {
    self.pos = entry_pos
  }
  let mut expires_at_ms : Int64? = None
  let mut idle_seconds : UInt64? = None
  let mut frequency : Byte? = None
  for opcode = first, offset = start {
    match opcode.to_int() {
      252 | 253 => {
        if expires_at_ms is Some(_) {
          raise DuplicateKeyMetadata(offset~, opcode~)
        }
        expires_at_ms = Some(
          if opcode == b'\xfc' {
            self.read_i64_le()
          } else {
            self.read_i32_le().to_int64() * 1000L
          },
        )
      }
      248 => {
        if idle_seconds is Some(_) {
          raise DuplicateKeyMetadata(offset~, opcode~)
        }
        idle_seconds = Some(self.read_count())
      }
      249 => {
        if frequency is Some(_) {
          raise DuplicateKeyMetadata(offset~, opcode~)
        }
        frequency = Some(self.read_u8())
      }
      _ => {
        if is_object_type(opcode) {
          return {
            start,
            type_offset: offset,
            object_type: opcode,
            expires_at_ms,
            idle_seconds,
            frequency,
          }
        }
        if opcode.to_int() >= 245 {
          raise DanglingKeyMetadata(offset=start)
        }
        raise UnsupportedOpcode(offset~, opcode~)
      }
    }
    let next_offset = self.pos
    let next_opcode = self.read_u8()
    continue next_opcode, next_offset
  }
}
