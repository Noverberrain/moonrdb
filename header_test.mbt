// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn header_error(
  input : Bytes,
  max_input_bytes~ : Int32 = 64 * 1024 * 1024,
) -> @moonrdb.ParseError raise {
  try @moonrdb.read_header(input, max_input_bytes~) catch {
    error => error
  } noraise {
    _ => fail("expected header failure")
  }
}

///|
test "header accepts version 11 without claiming body validation" {
  assert_eq(@moonrdb.read_header(b"REDIS0011"), 11)
  assert_eq(@moonrdb.read_header(b"REDIS0011\x00garbage"), 11)
}

///|
test "header rejects each truncated prefix" {
  let input = b"REDIS0011"
  for length in 0..<9 {
    let error = header_error(input[:length].to_owned())
    guard error is UnexpectedEnd(offset=0, needed=9UL, remaining~) else {
      fail("expected truncated header")
    }
    assert_eq(remaining, length)
  }
}

///|
test "header reports exact invalid magic offset" {
  let input = b"REDIS0011"
  for offset in 0..<5 {
    let bad = Bytes::makei(9, i => if i == offset { 0 } else { input[i] })
    let error = header_error(bad)
    guard error is InvalidMagic(offset=actual) else {
      fail("expected invalid magic")
    }
    assert_eq(actual, offset)
  }
}

///|
test "header rejects all non ASCII decimal version bytes" {
  let input = b"REDIS0011"
  for offset in 5..<9 {
    for value in 0..<256 {
      if value < 48 || value > 57 {
        let bad = Bytes::makei(9, i => {
          if i == offset {
            value.to_byte()
          } else {
            input[i]
          }
        })
        let error = header_error(bad)
        guard error is InvalidVersionDigit(offset=actual) else {
          fail("expected invalid version digit")
        }
        assert_eq(actual, offset)
      }
    }
  }
}

///|
test "header rejects versions outside the explicit support policy" {
  let cases : Array[(Bytes, Int32)] = [
    (b"REDIS0000", 0),
    (b"REDIS0010", 10),
    (b"REDIS0012", 12),
    (b"REDIS9999", 9999),
  ]
  for (input, expected) in cases {
    let error = header_error(input)
    guard error is UnsupportedVersion(offset=5, version~) else {
      fail("expected unsupported version")
    }
    assert_eq(version, expected)
  }
}

///|
test "input limit is checked before reading or indexing" {
  assert_eq(@moonrdb.read_header(b"REDIS0011", max_input_bytes=9), 11)
  assert_true(
    header_error(b"REDIS0011", max_input_bytes=8)
    is InputTooLarge(offset=0, size=9, limit=8),
  )
  assert_true(
    header_error(b"REDIS0011!", max_input_bytes=9)
    is InputTooLarge(offset=0, size=10, limit=9),
  )
  assert_true(
    header_error(b"", max_input_bytes=0)
    is UnexpectedEnd(offset=0, needed=9UL, remaining=0),
  )
  assert_true(
    header_error(b"", max_input_bytes=-1)
    is InvalidInputLimit(offset=0, limit=-1),
  )
}

///|
async test "real Redis snapshot header and each truncated header prefix" {
  let input = @fs.read_binary("fixtures/redis-7.2.5/empty.rdb")
  assert_eq(input.length(), 88)
  assert_eq(@moonrdb.read_header(input), 11)
  for length in 0..<9 {
    assert_true(header_error(input[:length].to_owned()) is UnexpectedEnd(..))
  }
}
