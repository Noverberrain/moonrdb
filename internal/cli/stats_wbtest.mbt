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
    Stats(path="file", max_input_bytes=67108864),
  )
}
