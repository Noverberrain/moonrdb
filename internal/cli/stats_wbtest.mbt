// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
async test "stats real mixed snapshot volume conservation and expiry" {
  let input = @fs.read_binary(
    "fixtures/redis-7.2.5-sorted-sets/sorted-sets.rdb",
  )
  let report = stats_report(@moonrdb.parse(input))
  assert_true(report.contains("keys: 8\n"))
  assert_true(report.contains("db 2 type SortedSet: keys=3"))
  assert_true(report.contains("with_expiry=1 permanent=2"))
  assert_true(report.contains("accounting_matches: true"))
  assert_true(report.contains("checksum: valid (CRC64)"))
  assert_eq(
    parse_args(["stats", "file"]),
    Stats(path="file", max_input_bytes=67108864, at_ms=None, prefixes=[]),
  )
}

///|
async test "stats explicit reference time prefix overlaps and stable defaults" {
  let snapshot = @moonrdb.parse(
    @fs.read_binary("fixtures/redis-7.2.5-sorted-sets/sorted-sets.rdb"),
  )
  let baseline = stats_report(snapshot)
  assert_true(baseline.contains("expiry_evaluation: not_requested"))
  assert_false(baseline.contains("expired:"))
  let report = stats_report(snapshot, at_ms=Some(4102444800123L), prefixes=[
    "", "long-", "missing",
  ])
  assert_true(report.contains("expired: 1\n"))
  assert_true(report.contains("permanent: 7\n"))
  assert_true(report.contains("keys=8 serialized_bytes="))
  assert_true(report.contains("keys=1 serialized_bytes="))
  assert_true(report.contains("keys=0 serialized_bytes=0"))
  assert_true(report.contains("accounting_matches: true"))
  assert_eq(stats_report(snapshot), baseline)
  let args = parse_args([
    "stats", "f", "--at", "2100-01-01T00:00:00.123Z", "--prefix", "user:",
  ])
  assert_eq(
    args,
    Stats(path="f", max_input_bytes=67108864, at_ms=Some(4102444800123L), prefixes=[
      "user:",
    ]),
  )
  for
    bad in [
      ["stats", "f", "--at", "x"],
      ["stats", "f", "--prefix"],
      ["stats", "f", "--prefix", "a", "--prefix", "a"],
      [
        "stats", "f", "--at", "1970-01-01T00:00:00Z", "--at", "1970-01-01T00:00:00Z",
      ],
    ] {
    usage_fails(bad)
  }
}

///|
test "prefix matching is binary safe including empty and Unicode" {
  assert_true(bytes_prefix(b"\x00\xffx", b"\x00\xff"))
  assert_true(bytes_prefix(b"x", b""))
  assert_false(bytes_prefix(b"x", b"xx"))
  assert_true(bytes_prefix(@utf8.encode("用户:1"), @utf8.encode("用户:")))
}
