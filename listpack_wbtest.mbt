// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn packed(body : Bytes, elements~ : Int32 = 2) -> Bytes {
  let header = (body.length() + 7).to_uint64().to_le_bytes()[:4].to_owned()
  header +
  ([(elements & 255).to_byte(), ((elements >> 8) & 255).to_byte()] : Bytes) +
  body +
  b"\xff"
}

///|
fn packed_entries(
  input : Bytes,
  max_string_bytes~ : Int32 = 1024 * 1024,
  max_hash_entries~ : Int32 = 100000,
) -> Array[HashEntry] raise ParseError {
  let budget : DecodeBudget = { limit: 64 * 1024 * 1024, used: 0, }
  decode_hash_listpack(input, 100, max_string_bytes, max_hash_entries, budget)
}

///|
test "listpack integer encodings preserve all signed width extremes" {
  let cases : Array[(Bytes, Bytes)] = [
    (b"\x00\x01", b"0"),
    (b"\x7f\x01", b"127"),
    (b"\xcf\xff\x02", b"4095"),
    (b"\xd0\x00\x02", b"-4096"),
    (b"\xdf\xff\x02", b"-1"),
    (b"\xf1\x00\x80\x03", b"-32768"),
    (b"\xf1\xff\x7f\x03", b"32767"),
    (b"\xf2\x00\x00\x80\x04", b"-8388608"),
    (b"\xf2\xff\xff\x7f\x04", b"8388607"),
    (b"\xf3\x00\x00\x00\x80\x05", b"-2147483648"),
    (b"\xf3\xff\xff\xff\x7f\x05", b"2147483647"),
    (b"\xf4\x00\x00\x00\x00\x00\x00\x00\x80\x09", b"-9223372036854775808"),
    (b"\xf4\xff\xff\xff\xff\xff\xff\xff\x7f\x09", b"9223372036854775807"),
  ]
  for (entry, expected) in cases {
    let result = packed_entries(packed(b"\x81f\x02" + entry))
    assert_eq(result[0].value, expected)
  }
}

///|
test "listpack binary empty and leading zero strings remain exact bytes" {
  let result = packed_entries(packed(b"\x80\x01\x82\x00\xff\x03"))
  assert_eq(result[0].field, b"")
  assert_eq(result[0].value, b"\x00\xff")
  assert_eq(
    packed_entries(packed(b"\x81f\x02\x82" + b"01" + b"\x03"))[0].value,
    b"01",
  )
}

///|
test "listpack 12 and 32 bit string lengths and back-length width boundaries" {
  let cases : Array[(Bytes, Int32, Bytes)] = [
    (b"\xe0\x7d", 125, b"\x7f"),
    (b"\xe0\x7e", 126, b"\x01\x80"),
    (b"\xef\xff", 4095, b"\x20\x81"),
    (b"\xf0\x00\x10\x00\x00", 4096, b"\x20\x85"),
    (b"\xf0\xf9\x3f\x00\x00", 16377, b"\x7f\xfe"),
    (b"\xf0\xfa\x3f\x00\x00", 16378, b"\x00\xff\xff"),
  ]
  for (header, length, backlen) in cases {
    let value = b"x".repeat(length)
    assert_eq(
      packed_entries(packed(b"\x81f\x02" + header + value + backlen))[0].value,
      value,
    )
  }
  for
    (length, expected) in [
      (127UL, 1),
      (128UL, 2),
      (16382UL, 2),
      (16383UL, 3),
      (2097150UL, 3),
      (2097151UL, 4),
      (268435454UL, 4),
      (268435455UL, 5),
    ] {
    assert_eq(listpack_backlen_size(length), expected)
  }
}

///|
test "listpack header and terminator validation" {
  let valid = packed(b"\x81f\x02\x81v\x02")
  for length in 0..<valid.length() {
    assert_true(
      read_error(() => packed_entries(valid[:length].to_owned()))
      is InvalidListpack(..),
    )
  }
  let bad_total = Bytes::makei(valid.length(), i => {
    if i == 0 {
      0
    } else {
      valid[i]
    }
  })
  assert_true(
    read_error(() => packed_entries(bad_total))
    is InvalidListpack(inner_offset=0, ..),
  )
  let bad_end = Bytes::makei(valid.length(), i => {
    if i == valid.length() - 1 {
      0
    } else {
      valid[i]
    }
  })
  assert_true(read_error(() => packed_entries(bad_end)) is InvalidListpack(..))
  assert_true(
    read_error(() => packed_entries(packed(b"\xff\x00"))) is InvalidListpack(..),
  )
}

///|
test "listpack rejects incorrect counts odd pairs empty hashes and duplicates" {
  assert_true(
    read_error(() => packed_entries(packed(b"\x81f\x02\x81v\x02", elements=4)))
    is InvalidListpack(inner_offset=4, ..),
  )
  assert_true(
    read_error(() => packed_entries(packed(b"\x81f\x02", elements=1)))
    is InvalidHash(..),
  )
  assert_true(
    read_error(() => packed_entries(packed(b"\x81f\x02", elements=65535)))
    is InvalidHash(..),
  )
  assert_true(
    read_error(() => packed_entries(packed(b"", elements=0)))
    is InvalidHash(reason="empty hash", ..),
  )
  // Integer field 1 and raw field "1" are the same semantic Hash field.
  assert_true(
    read_error(() => {
      packed_entries(
        packed(b"\x01\x01\x00\x01\x81" + b"1" + b"\x02\x00\x01", elements=4),
      )
    })
    is InvalidHash(reason="duplicate field", ..),
  )
}

///|
test "listpack unknown header count still scans and enforces Hash pair limits" {
  let input = packed(b"\x81f\x02\x81v\x02", elements=65535)
  assert_eq(packed_entries(input)[0].value, b"v")
  assert_true(
    read_error(() => packed_entries(input, max_hash_entries=0))
    is ResourceLimitExceeded(resource="hash-entries", ..),
  )
}

///|
test "listpack rejects every reserved tag incorrect back lengths and overlong string claims" {
  for tag in 245..<255 {
    assert_true(
      read_error(() => packed_entries(packed(([tag.to_byte()] : Bytes))))
      is InvalidListpack(..),
    )
  }
  assert_true(
    read_error(() => packed_entries(packed(b"\x81f\x00\x81v\x02")))
    is InvalidListpack(offset=100, inner_offset=8, ..),
  )
  assert_true(
    read_error(() => packed_entries(packed(b"\x81f\x02\xf0\xff\xff\xff\xff")))
    is ResourceLimitExceeded(resource="string-bytes", actual=4294967295UL, ..),
  )
  assert_true(
    read_error(() => packed_entries(packed(b"\x81f\x02\xe0\x40x")))
    is InvalidListpack(..),
  )
}
