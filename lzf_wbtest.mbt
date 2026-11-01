// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
test "LZF literal run lengths 1 through 32" {
  for count in 1..<=32 {
    let plain = Bytes::makei(count, i => i.to_byte())
    let compressed = ([(count - 1).to_byte()] : Bytes) + plain
    assert_eq(decompress_lzf(compressed[:], count, 0), plain)
  }
}

///|
test "LZF overlap non-overlap and maximum extended length" {
  assert_eq(decompress_lzf(b"\x00a\x60\x00"[:], 6, 0), b"aaaaaa")
  assert_eq(decompress_lzf(b"\x05abcdef\x20\x05"[:], 9, 0), b"abcdefabc")
  assert_eq(decompress_lzf(b"\x00a\xe0\xff\x00"[:], 265, 0), b"a".repeat(265))
}

///|
test "LZF maximum back-reference distance 8192" {
  let plain = Bytes::makei(8192, i => (i & 255).to_byte())
  let mut compressed = b""
  for block in 0..<256 {
    compressed = compressed +
      b"\x1f" +
      plain[block * 32:block * 32 + 32].to_owned()
  }
  compressed = compressed + b"\x3f\xff"
  assert_eq(decompress_lzf(compressed[:], 8195, 0), plain + b"\x00\x01\x02")
}

///|
test "LZF invalid literals references truncated tokens and size mismatches" {
  let cases : Array[(Bytes, Int32)] = [
    (b"\x00", 1),
    (b"\x01a", 2),
    (b"\xe0", 1),
    (b"\xe0\x00", 1),
    (b"\x20", 1),
    (b"\x20\x00", 3),
    (b"\x00a\x20\x01", 4),
    (b"\x00a\x60\x00", 5),
    (b"\x00a", 2),
    (b"\x00a\x00b", 1),
  ]
  for (input, count) in cases {
    let error = read_error(() => decompress_lzf(input[:], count, 17))
    guard error is InvalidLzf(offset~, ..) else { fail("expected invalid LZF") }
    assert_true(offset >= 17 && offset <= 17 + input.length())
  }
}

///|
test "string failure restores both cursor and decoded budget" {
  let r = reader(b"\xaa\xc3\x02\x03\x20\x00")
  ignore(r.read_u8())
  let budget : DecodeBudget = { limit: 100, used: 5, }
  assert_true(
    read_error(() => {
      r.read_string(100, budget, allow_lzf=true, resource="string-bytes")
    })
    is InvalidLzf(..),
  )
  assert_eq(r.pos, 1)
  assert_eq(budget.used, 5)
}
