// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
test "export arguments defaults filters and invalid combinations" {
  assert_eq(
    parse_args(["export", "f"]),
    Export(
      path="f",
      max_input_bytes=67108864,
      db=None,
      prefix=None,
      output=None,
    ),
  )
  assert_eq(
    parse_args([
      "export", "--db", "18446744073709551615", "--prefix", "", "--format", "jsonl",
      "--output", "out", "--", "-f",
    ]),
    Export(
      path="-f",
      max_input_bytes=67108864,
      db=Some(0xffffffffffffffffUL),
      prefix=Some(""),
      output=Some("out"),
    ),
  )
  for
    args in [
      ["export", "f", "--db", "18446744073709551616"],
      ["export", "f", "--db", "-1"],
      ["export", "f", "--db", ""],
      ["export", "f", "--db", "1_0"],
      ["export", "f", "--db", "0", "--db", "1"],
      ["export", "f", "--prefix", "a", "--prefix", "b"],
      ["export", "f", "--format", "json"],
      ["export", "f", "--format", "jsonl", "--format", "jsonl"],
      ["export", "f", "--output", ""],
      ["export", "f", "--output", "-"],
      ["export", "f", "--at", "1970-01-01T00:00:00Z"],
    ] {
    usage_fails(args)
  }
}

///|
test "export intersection filter preserves binary keys and exact bytes" {
  let snapshot = @moonrdb.parse(
    b"REDIS0011\x00\x02\x00\xff\x01v\xff\x00\x00\x00\x00\x00\x00\x00\x00",
  )
  let record = snapshot.records[0]
  assert_true(export_match(record, None, None))
  assert_true(export_match(record, Some(0UL), Some(b"\x00")))
  assert_false(export_match(record, Some(2UL), Some(b"\x00")))
  assert_false(export_match(record, None, Some(b"x")))
  assert_true(record_json(record).stringify().contains("AP8="))
}
