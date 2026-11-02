// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
test "UTC calendar exact epochs leap years and milliseconds" {
  assert_eq(parse_at("1970-01-01T00:00:00Z"), 0L)
  assert_eq(parse_at("1969-12-31T23:59:59.999Z"), -1L)
  assert_eq(parse_at("2000-02-29T00:00:00Z"), 951782400000L)
  assert_eq(parse_at("2100-01-01T00:00:00.123Z"), 4102444800123L)
  assert_eq(parse_at("0001-01-01T00:00:00Z"), -62135596800000L)
  assert_eq(parse_at("9999-12-31T23:59:59.999Z"), 253402300799999L)
}

///|
test "UTC calendar rejects invalid dates offsets leap seconds and fractions" {
  for
    text in [
      "", "0", "2026-02-29T00:00:00Z", "1900-02-29T00:00:00Z", "2100-02-29T00:00:00Z",
      "0000-01-01T00:00:00Z", "2026-00-01T00:00:00Z", "2026-13-01T00:00:00Z", "2026-04-31T00:00:00Z",
      "2026-01-00T00:00:00Z", "2026-01-01T24:00:00Z", "2026-01-01T00:60:00Z", "2026-01-01T00:00:60Z",
      "2026-01-01t00:00:00Z", "2026-01-01T00:00:00+00:00", "2026-01-01T00:00:00.1Z",
    ] {
    try parse_at(text) catch {
      InvalidArguments => ()
    } noraise {
      _ => fail(text)
    }
  }
}

///|
test "TTL buckets endpoints and full signed timestamp range" {
  assert_eq(ttl_bucket(None, 0L), 0)
  assert_eq(ttl_bucket(Some(0L), 0L), 1)
  assert_eq(ttl_bucket(Some(-1L), 0L), 1)
  for
    (delta, bucket) in [
      (1L, 2),
      (3600000L, 2),
      (3600001L, 3),
      (86400000L, 3),
      (86400001L, 4),
      (604800000L, 4),
      (604800001L, 5),
      (2592000000L, 5),
      (2592000001L, 6),
    ] {
    assert_eq(ttl_bucket(Some(delta), 0L), bucket)
  }
  assert_eq(ttl_bucket(Some(9223372036854775807L), -9223372036854775808L), 6)
}
