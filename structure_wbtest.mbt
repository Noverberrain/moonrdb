// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
test "Redis CRC64 official check vector and empty input" {
  assert_eq(crc64(b""[:]), 0UL)
  assert_eq(crc64(b"123456789"[:]), 0xe9c6d914c4b8d9caUL)
}

///|
test "key prefix decodes milliseconds idle seconds and frequency without a clock" {
  let input = b"\xfc\x00\x00\x00\x00\x00\x01\x00\x00\xf8\x81\xff\xff\xff\xff\xff\xff\xff\xff\xf9\xff\x00"
  let r = reader(input)
  let first = r.read_u8()
  let prefix = r.read_key_prefix(first, 0)
  assert_eq(prefix.start, 0)
  assert_eq(prefix.type_offset, input.length() - 1)
  assert_eq(prefix.object_type, b'\x00')
  assert_eq(prefix.expires_at_ms, Some(1099511627776L))
  assert_eq(prefix.idle_seconds, Some(0xffffffffffffffffUL))
  assert_eq(prefix.frequency, Some(b'\xff'))
  assert_eq(r.pos, input.length())
}

///|
test "expiration keeps signed 64-bit values and widens old signed seconds before scaling" {
  let cases : Array[(Bytes, Int64)] = [
    (b"\xfc\xff\xff\xff\xff\xff\xff\xff\x7f\x00", 9223372036854775807L),
    (b"\xfc\x00\x00\x00\x00\x00\x00\x00\x80\x00", -9223372036854775808L),
    (b"\xfd\xff\xff\xff\x7f\x00", 2147483647000L),
    (b"\xfd\x00\x00\x00\x80\x00", -2147483648000L),
  ]
  for (input, expected) in cases {
    let r = reader(input)
    let opcode = r.read_u8()
    let prefix = r.read_key_prefix(opcode, 0)
    assert_eq(prefix.expires_at_ms, Some(expected))
    assert_eq(prefix.idle_seconds, None)
    assert_eq(prefix.frequency, None)
  }
}

///|
test "metadata reader rejects all truncated prefixes atomically" {
  let cases = [
    b"\xfc\x01\x02\x03\x04\x05\x06\x07\x08\x00", b"\xfd\x01\x02\x03\x04\x00", b"\xf8\x40\x40\x00",
    b"\xf9\xff\x00",
  ]
  for input in cases {
    for size in 1..<input.length() {
      let r = reader(input[:size].to_owned())
      let opcode = r.read_u8()
      assert_true(
        read_error(() => r.read_key_prefix(opcode, 0)) is UnexpectedEnd(..),
      )
      assert_eq(r.pos, 1)
    }
  }
}

///|
test "duplicate expiry idle or frequency is rejected at the duplicate opcode" {
  let cases : Array[(Bytes, Int32)] = [
    (b"\xfc\x00\x00\x00\x00\x00\x00\x00\x00\xfd\x00\x00\x00\x00\x00", 9),
    (b"\xf8\x00\xf8\x00\x00", 2),
    (b"\xf9\x00\xf9\x00\x00", 2),
  ]
  for (input, expected) in cases {
    let r = reader(input)
    let first = r.read_u8()
    let error = read_error(() => r.read_key_prefix(first, 0))
    guard error is DuplicateKeyMetadata(offset~, ..) else {
      fail("expected duplicate metadata")
    }
    assert_eq(offset, expected)
  }
}

///|
test "orphan metadata and unknown following opcode fail without skipping" {
  for value in [245, 246, 247, 250, 251, 254, 255] {
    let r = reader(b"\xf9\x00" + ([value.to_byte()] : Bytes))
    let first = r.read_u8()
    assert_true(
      read_error(() => r.read_key_prefix(first, 0))
      is DanglingKeyMetadata(offset=0),
    )
  }
  let r = reader(b"\xf9\x00\x08")
  let first = r.read_u8()
  assert_true(
    read_error(() => r.read_key_prefix(first, 0))
    is UnsupportedOpcode(offset=2, opcode=b'\x08'),
  )
}
