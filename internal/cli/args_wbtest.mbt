// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn usage_fails(args : Array[String]) -> Unit raise {
  try parse_args(args[:]) catch {
    InvalidArguments => ()
  } noraise {
    _ => fail("expected usage error")
  }
}

///|
test "help accepts only explicit complete forms" {
  for args in [["--help"], ["-h"], ["inspect", "--help"], ["inspect", "-h"]] {
    assert_eq(parse_args(args[:]), Help)
  }
  for
    args in [
      [],
      ["inspect"],
      ["--help", "x"],
      ["export", "x"],
      ["inspect", "x", "--help"],
    ] {
    usage_fails(args)
  }
}

///|
test "inspect path options and end of options" {
  assert_eq(
    parse_args(["inspect", "dump.rdb"]),
    Inspect(path="dump.rdb", max_input_bytes=67108864),
  )
  for
    args in [
      ["inspect", "dump.rdb", "--max-input-bytes", "18"],
      ["inspect", "--max-input-bytes", "18", "dump.rdb"],
    ] {
    assert_eq(parse_args(args[:]), Inspect(path="dump.rdb", max_input_bytes=18))
  }
  assert_eq(
    parse_args(["inspect", "--", "-binary.rdb"]),
    Inspect(path="-binary.rdb", max_input_bytes=67108864),
  )
  assert_eq(
    parse_args(["inspect", "路径 with spaces.rdb"]),
    Inspect(path="路径 with spaces.rdb", max_input_bytes=67108864),
  )
}

///|
test "inspect rejects ignored options and multiple paths" {
  for
    args in [
      ["inspect", "a", "b"],
      ["inspect", ""],
      ["inspect", "-a"],
      ["inspect", "a", "--at", "0"],
      ["inspect", "--"],
      ["inspect", "a", "--max-input-bytes"],
      ["inspect", "a", "--max-input-bytes", "1", "--max-input-bytes", "2"],
      ["inspect", "--", "a", "--max-input-bytes", "1"],
    ] {
    usage_fails(args)
  }
}

///|
test "input limit is strict positive decimal with checked accumulation" {
  for
    value in [
      "0", "-1", "+1", "1_000", "0x10", "1.5", " 1", "1 ", "", "2147483648", "999999999999999999999999",
    ] {
    usage_fails(["inspect", "a", "--max-input-bytes", value])
  }
  assert_eq(positive_limit("2147483647"), 2147483647)
  assert_eq(positive_limit("00018"), 18)
}
