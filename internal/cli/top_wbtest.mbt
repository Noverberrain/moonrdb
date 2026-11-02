// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn reference_top(
  records : Array[@moonrdb.RdbRecord],
  limit : Int32,
) -> Array[Int32] {
  let ranks = records.mapi((index, record) => {
    let (db, key, size, start, _, _, _, _) = top_meta(record)
    TopRank::{ size: -size.reinterpret_as_int64(), db, key, start, index, }
  })
  ranks.sort()
  ranks[:Int32::min(limit, ranks.length())].to_owned().map(r => r.index)
}

///|
async test "bounded TopN matches full sorting for every limit across all fixtures" {
  for
    (folder, name) in [
      ("redis-7.2.5", "empty"),
      ("redis-7.2.5-no-checksum", "empty"),
      ("redis-7.2.5-strings", "strings"),
      ("redis-7.2.5-hashes", "hashes"),
      ("redis-7.2.5-lists", "lists"),
      ("redis-7.2.5-sets", "sets"),
      ("redis-7.2.5-sorted-sets", "sorted-sets"),
    ] {
    let snapshot = @moonrdb.parse(
      @fs.read_binary("fixtures/\{folder}/\{name}.rdb"),
    )
    for limit in 0..<(snapshot.records.length() + 3) {
      assert_eq(
        top_indices(snapshot.records, limit),
        reference_top(snapshot.records, limit),
      )
    }
    assert_true(top_report(snapshot, 20).contains("status: complete"))
  }
}

///|
test "ties use database binary key offset and final input index" {
  let snapshot = @moonrdb.parse(
    b"REDIS0011\x00\x01z\x01v\x00\x01a\x01v\x00\x01a\x01v\xfe\x01\x00\x01a\x01v\xff\x00\x00\x00\x00\x00\x00\x00\x00",
  )
  assert_eq(top_indices(snapshot.records, 4), [1, 2, 0, 3])
  assert_eq(top_indices(snapshot.records, 1), [1])
  let repeated = [snapshot.records[1], snapshot.records[1]]
  assert_eq(top_indices(repeated, 1), [0])
}

///|
test "heap adversarial insertion orders repeated sizes and binary key output" {
  let bytes = b"REDIS0011\x00\x02\x00\xff\x01v\xff\x00\x00\x00\x00\x00\x00\x00\x00"
  let seed = @moonrdb.parse(bytes).records[0]
  let records = Array::makei(300, i => {
    guard seed is String(r) else { abort("expected String") }
    @moonrdb.RdbRecord::String({
      ..r,
      key: b"\{(i*37)%101}",
      serialized_bytes: (i * 71 % 113).to_uint64(),
      record_start: i,
    })
  })
  for limit in [1, 2, 3, 19, 20, 150, 299, 300, 301] {
    assert_eq(top_indices(records, limit), reference_top(records, limit))
  }
  let report = top_report(@moonrdb.parse(bytes), 1)
  assert_true(report.contains("key_base64=AP8="))
  assert_true(report.contains("value_bytes=1"))
}

///|
test "top accepts only supported ranking and bounded positive limits" {
  assert_eq(
    parse_args(["top", "f"]),
    Top(path="f", max_input_bytes=67108864, limit=20),
  )
  assert_eq(
    parse_args(["top", "--by", "serialized-bytes", "--limit", "1", "--", "-f"]),
    Top(path="-f", max_input_bytes=67108864, limit=1),
  )
  for
    args in [
      ["top", "f", "--limit", "0"],
      ["top", "f", "--limit", "10001"],
      ["top", "f", "--limit", "1", "--limit", "2"],
      ["top", "f", "--by", "ram"],
      ["top", "f", "--by", "serialized-bytes", "--by", "serialized-bytes"],
      ["top", "f", "--at", "1970-01-01T00:00:00Z"],
      ["inspect", "f", "--limit", "1"],
    ] {
    usage_fails(args)
  }
}

///|
test "binary key lexicographic order is not length-first order" {
  let a = TopRank::{ size: -10L, db: 0UL, key: b"aa", start: 0, index: 0, }
  let b = TopRank::{ size: -10L, db: 0UL, key: b"z", start: 1, index: 1, }
  assert_true(a.compare(b) < 0)
  assert_true(
    TopRank::{ ..a, key: b"\x00\xff", }.compare({ ..b, key: b"\xff", }) < 0,
  )
}
