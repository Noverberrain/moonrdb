// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn reader(input : Bytes) -> Reader raise ParseError {
  Reader::new(input, max_input_bytes=1024)
}

///|
fn[T] read_error(action : () -> T raise ParseError) -> ParseError raise {
  try action() catch {
    error => error
  } noraise {
    _ => fail("expected read failure")
  }
}

///|
test "reader consumes binary views and allows empty reads at EOF" {
  let r = reader(b"\x00\xff\x80")
  assert_eq(r.read_bytes(0UL).length(), 0)
  assert_eq(r.read_u8(), b'\x00')
  assert_eq(r.read_bytes(2UL).to_owned(), b"\xff\x80")
  assert_eq(r.pos, 3)
  assert_eq(r.remaining(), 0)
  assert_eq(r.read_bytes(0UL).length(), 0)
  assert_true(
    read_error(() => r.read_u8())
    is UnexpectedEnd(offset=3, needed=1UL, remaining=0),
  )
  assert_eq(r.pos, 3)
}

///|
test "huge byte counts fail before UInt64 narrowing and offset addition" {
  let r = reader(b"\xaa\xbb")
  ignore(r.read_u8())
  let counts : Array[UInt64] = [
    2UL, 2147483648UL, 4294967296UL, 0x8000000000000000UL, 0xffffffffffffffffUL,
  ]
  for count in counts {
    let error = read_error(() => r.read_bytes(count))
    guard error is UnexpectedEnd(offset=1, needed~, remaining=1) else {
      fail("expected bounded byte read error")
    }
    assert_eq(needed, count)
    assert_eq(r.pos, 1)
  }
  assert_eq(r.read_u8(), b'\xbb')
}

///|
test "little endian unsigned values preserve all bits" {
  assert_eq(reader(b"\x04\x03\x02\x01").read_u32_le(), 0x01020304U)
  assert_eq(reader(b"\xff\xff\xff\xff").read_u32_le(), 0xffffffffU)
  assert_eq(
    reader(b"\x08\x07\x06\x05\x04\x03\x02\x01").read_u64_le(),
    0x0102030405060708UL,
  )
  assert_eq(
    reader(b"\xff\xff\xff\xff\xff\xff\xff\xff").read_u64_le(),
    0xffffffffffffffffUL,
  )
}

///|
test "signed integer widths decode minimum maximum and minus one" {
  let i8s : Array[(Bytes, Int32)] = [
    (b"\x00", 0),
    (b"\x7f", 127),
    (b"\x80", -128),
    (b"\xff", -1),
  ]
  for (input, expected) in i8s {
    assert_eq(reader(input).read_i8(), expected)
  }
  let i16s : Array[(Bytes, Int32)] = [
    (b"\x00\x00", 0),
    (b"\xff\x7f", 32767),
    (b"\x00\x80", -32768),
    (b"\xff\xff", -1),
  ]
  for (input, expected) in i16s {
    assert_eq(reader(input).read_i16_le(), expected)
  }
  let i32s : Array[(Bytes, Int32)] = [
    (b"\x00\x00\x00\x00", 0),
    (b"\xff\xff\xff\x7f", 2147483647),
    (b"\x00\x00\x00\x80", -2147483648),
    (b"\xff\xff\xff\xff", -1),
  ]
  for (input, expected) in i32s {
    assert_eq(reader(input).read_i32_le(), expected)
  }
  let i64s : Array[(Bytes, Int64)] = [
    (b"\x00\x00\x00\x00\x00\x00\x00\x00", 0L),
    (b"\xff\xff\xff\xff\xff\xff\xff\x7f", 9223372036854775807L),
    (b"\x00\x00\x00\x00\x00\x00\x00\x80", -9223372036854775808L),
    (b"\xff\xff\xff\xff\xff\xff\xff\xff", -1L),
  ]
  for (input, expected) in i64s {
    assert_eq(reader(input).read_i64_le(), expected)
  }
}

///|
test "fixed width signed reads reject every truncated prefix atomically" {
  let input = b"\x01\x02\x03\x04\x05\x06\x07\x08"
  for width in [1, 2, 4, 8] {
    for size in 0..<width {
      let r = reader(b"\xaa" + input[:size].to_owned())
      ignore(r.read_u8())
      let error = read_error(() => {
        match width {
          1 => ignore(r.read_i8())
          2 => ignore(r.read_i16_le())
          4 => ignore(r.read_i32_le())
          _ => ignore(r.read_i64_le())
        }
      })
      guard error is UnexpectedEnd(offset=1, needed~, remaining~) else {
        fail("expected truncated numeric value")
      }
      assert_eq(needed, width.to_uint64())
      assert_eq(remaining, size)
      assert_eq(r.pos, 1)
    }
  }
}

///|
test "header cursor advances only on success and errors use absolute offsets" {
  let r = reader(b"\x00REDIS0011!")
  ignore(r.read_u8())
  assert_eq(r.read_header(), 11)
  assert_eq(r.pos, 10)
  assert_eq(r.read_u8(), b'!')
  let bad = reader(b"\x00REDIS00x1")
  ignore(bad.read_u8())
  assert_true(
    read_error(() => bad.read_header()) is InvalidVersionDigit(offset=8),
  )
  assert_eq(bad.pos, 1)
}
