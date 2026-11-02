// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn decode_intset(
  input : Bytes,
  base : Int32,
  max_string_bytes : Int32,
  budget : DecodeBudget,
  sets : SetBudget,
) -> (Array[Bytes], Int32) raise ParseError {
  if input.length() < 8 {
    raise InvalidIntset(offset=base, inner_offset=0, reason="short header")
  }
  let reader = Reader::new(input, max_input_bytes=input.length())
  let width = reader.read_unsigned(4, little_endian=true)
  if width != 2UL && width != 4UL && width != 8UL {
    raise InvalidIntset(
      offset=base,
      inner_offset=0,
      reason="invalid integer width",
    )
  }
  let count = reader.read_unsigned(4, little_endian=true)
  // count is a UInt32 value. Widen before multiplication; never Int32 math.
  if 8UL + count * width != input.length().to_uint64() {
    raise InvalidIntset(offset=base, inner_offset=4, reason="length mismatch")
  }
  if count == 0UL {
    raise InvalidSet(offset=base, reason="empty set")
  }
  sets.charge(count, base)
  let members = []
  let mut previous : Int64? = None
  for _ in 0..<count.to_int() {
    let inner_offset = reader.pos
    let value = match width {
      2UL => reader.read_i16_le().to_int64()
      4UL => reader.read_i32_le().to_int64()
      _ => reader.read_i64_le()
    }
    if previous is Some(old) && value <= old {
      raise InvalidIntset(
        offset=base,
        inner_offset~,
        reason="members not strictly increasing",
      )
    }
    previous = Some(value)
    let bytes = b"\{value}"
    check_resource_limit(
      "string-bytes",
      base,
      bytes.length().to_uint64(),
      max_string_bytes,
    )
    budget.charge(bytes.length().to_uint64(), base)
    members.push(bytes)
  }
  (members, width.to_int())
}
