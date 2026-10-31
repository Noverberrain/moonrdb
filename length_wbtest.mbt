// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
test "all six and fourteen bit length values" {
  for value in 0..<64 {
    let input : Bytes = [value.to_byte()]
    assert_eq(reader(input).read_count(), value.to_uint64())
  }
  for value in 0..<16384 {
    let input : Bytes = [
      (0x40 | (value >> 8)).to_byte(),
      (value & 255).to_byte(),
    ]
    assert_eq(reader(input).read_count(), value.to_uint64())
  }
}

///|
test "length width boundaries and network byte order" {
  let cases : Array[(Bytes, UInt64)] = [
    (b"\x00", 0UL),
    (b"\x3f", 63UL),
    (b"\x40\x40", 64UL),
    (b"\x7f\xff", 16383UL),
    (b"\x80\x00\x00\x40\x00", 16384UL),
    (b"\x80\x01\x02\x03\x04", 0x01020304UL),
    (b"\x80\xff\xff\xff\xff", 4294967295UL),
    (b"\x81\x00\x00\x00\x01\x00\x00\x00\x00", 4294967296UL),
    (b"\x81\x01\x02\x03\x04\x05\x06\x07\x08", 0x0102030405060708UL),
    (b"\x81\xff\xff\xff\xff\xff\xff\xff\xff", 0xffffffffffffffffUL),
    // Redis's loader also accepts lengths stored using a wider representation.
    (b"\x40\x00", 0UL),
    (b"\x80\x00\x00\x00\x00", 0UL),
    (b"\x81\x00\x00\x00\x00\x00\x00\x00\x00", 0UL),
  ]
  for (input, expected) in cases {
    let r = reader(input + b"\xaa")
    assert_eq(r.read_length(), Plain(expected))
    assert_eq(r.pos, input.length())
    assert_eq(r.read_u8(), b'\xaa')
    assert_eq(reader(input).read_count(), expected)
  }
}

///|
test "all encoded string markers remain distinct from byte counts" {
  let cases : Array[(Bytes, StringEncoding)] = [
    (b"\xc0", Int8),
    (b"\xc1", Int16),
    (b"\xc2", Int32),
    (b"\xc3", Lzf),
  ]
  for (input, encoding) in cases {
    let r = reader(b"\xaa" + input + b"\xbb")
    ignore(r.read_u8())
    assert_true(
      read_error(() => r.read_count()) is UnexpectedEncodedLength(offset=1),
    )
    assert_eq(r.pos, 1)
    assert_eq(r.read_length(), Encoded(encoding))
    assert_eq(r.pos, 2)
    assert_eq(r.read_u8(), b'\xbb')
  }
}

///|
test "length reader rejects all reserved length and unknown string encoding tags" {
  for value in 0x82..<0xc0 {
    let r = reader(b"\xaa" + ([value.to_byte()] : Bytes))
    ignore(r.read_u8())
    let error = read_error(() => r.read_length())
    guard error is InvalidLengthTag(offset=1, tag~) else {
      fail("expected invalid length tag")
    }
    assert_eq(tag, value.to_byte())
    assert_eq(r.pos, 1)
  }
  for value in 0xc4..<0x100 {
    let r = reader(([value.to_byte()] : Bytes))
    let error = read_error(() => r.read_length())
    guard error is InvalidStringEncoding(offset=0, encoding~) else {
      fail("expected invalid encoded string tag")
    }
    assert_eq(encoding, value & 0x3f)
    assert_eq(r.pos, 0)
  }
}

///|
test "length reader rejects every truncated prefix and restores the cursor" {
  let cases = [
    b"\x40\x40", b"\x80\x01\x02\x03\x04", b"\x81\x01\x02\x03\x04\x05\x06\x07\x08",
  ]
  for input in cases {
    for size in 0..<input.length() {
      let r = reader(b"\xaa" + input[:size].to_owned())
      ignore(r.read_u8())
      let error = read_error(() => r.read_length())
      guard error is UnexpectedEnd(offset~, needed~, remaining~) else {
        fail("expected truncated length")
      }
      assert_eq(offset, if size == 0 { 1 } else { 2 })
      assert_eq(
        needed,
        if size == 0 {
          1UL
        } else {
          (input.length() - 1).to_uint64()
        },
      )
      assert_eq(remaining, if size == 0 { 0 } else { size - 1 })
      assert_eq(r.pos, 1)
    }
  }
}

///|
test "maximum decoded length never becomes a wrapped byte count" {
  let r = reader(b"\x81\xff\xff\xff\xff\xff\xff\xff\xff")
  let count = r.read_count()
  assert_eq(count, 0xffffffffffffffffUL)
  assert_true(
    read_error(() => r.read_bytes(count))
    is UnexpectedEnd(offset=9, needed=0xffffffffffffffffUL, remaining=0),
  )
  assert_eq(r.pos, 9)
}
