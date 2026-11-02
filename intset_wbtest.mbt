// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn iset(width : UInt64, count : UInt64, values : Bytes) -> Bytes {
  width.to_le_bytes()[:4].to_owned() +
  count.to_le_bytes()[:4].to_owned() +
  values
}

///|
fn intset_values(
  input : Bytes,
  max_string_bytes~ : Int32 = 100,
  max_set_members~ : Int32 = 100,
) -> (Array[Bytes], Int32) raise ParseError {
  let budget : DecodeBudget = { limit: 1000, used: 0, }
  let sets : SetBudget = { limit: max_set_members, used: 0, }
  decode_intset(input, 100, max_string_bytes, budget, sets)
}

///|
test "intset little-endian signed widths and extremes" {
  let (shorts, width2) = intset_values(
    iset(2UL, 4UL, b"\x00\x80\xff\xff\x00\x00\xff\x7f"),
  )
  assert_eq(width2, 2)
  assert_eq(shorts, [b"-32768", b"-1", b"0", b"32767"])
  let (ints, width4) = intset_values(
    iset(
      4UL, 4UL, b"\x00\x00\x00\x80\xff\xff\xff\xff\x00\x00\x00\x00\xff\xff\xff\x7f",
    ),
  )
  assert_eq(width4, 4)
  assert_eq(ints, [b"-2147483648", b"-1", b"0", b"2147483647"])
  let (longs, width8) = intset_values(
    iset(
      8UL, 4UL, b"\x00\x00\x00\x00\x00\x00\x00\x80\xff\xff\xff\xff\xff\xff\xff\xff\x00\x00\x00\x00\x00\x00\x00\x00\xff\xff\xff\xff\xff\xff\xff\x7f",
    ),
  )
  assert_eq(width8, 8)
  assert_eq(longs, [
    b"-9223372036854775808", b"-1", b"0", b"9223372036854775807",
  ])
}

///|
test "intset wider historical encoding need not shrink with its current values" {
  let (values, width) = intset_values(
    iset(
      8UL, 2UL, b"\x01\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00",
    ),
  )
  assert_eq(width, 8)
  assert_eq(values, [b"1", b"2"])
}

///|
test "intset short header invalid widths and exact-size arithmetic" {
  let input = iset(2UL, 2UL, b"\x01\x00\x02\x00")
  for size in 0..<input.length() {
    assert_true(
      read_error(() => intset_values(input[:size].to_owned()))
      is InvalidIntset(..),
    )
  }
  for width in [0UL, 1UL, 3UL, 16UL, 4294967295UL] {
    assert_true(
      read_error(() => intset_values(iset(width, 0UL, b"")))
      is InvalidIntset(inner_offset=0, ..),
    )
  }
  assert_true(
    read_error(() => intset_values(input + b"\x00"))
    is InvalidIntset(inner_offset=4, ..),
  )
  assert_true(
    read_error(() => intset_values(iset(2UL, 0x80000000UL, b"")))
    is InvalidIntset(inner_offset=4, ..),
  )
  assert_true(
    read_error(() => intset_values(iset(8UL, 0xffffffffUL, b"")))
    is InvalidIntset(inner_offset=4, ..),
  )
  assert_true(
    read_error(() => intset_values(iset(2UL, 0UL, b"")))
    is InvalidSet(reason="empty set", ..),
  )
}

///|
test "intset rejects equal descending and signed-order-invalid values" {
  for payload in [b"\x01\x00\x01\x00", b"\x02\x00\x01\x00"] {
    assert_true(
      read_error(() => intset_values(iset(2UL, 2UL, payload)))
      is InvalidIntset(
        offset=100,
        inner_offset=10,
        reason="members not strictly increasing"
      ),
    )
  }
  assert_true(
    read_error(() => {
      intset_values(
        iset(
          8UL, 2UL, b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x80",
        ),
      )
    })
    is InvalidIntset(inner_offset=16, ..),
  )
}

///|
test "intset decimal length and Set budget limits are enforced" {
  let input = iset(2UL, 1UL, b"\x00\x80")
  assert_eq(intset_values(input, max_string_bytes=6).0, [b"-32768"])
  assert_true(
    read_error(() => intset_values(input, max_string_bytes=5))
    is ResourceLimitExceeded(resource="string-bytes", actual=6UL, ..),
  )
  assert_true(
    read_error(() => intset_values(input, max_set_members=0))
    is ResourceLimitExceeded(resource="set-members", actual=1UL, ..),
  )
}
