// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
// Minimal library use: no filesystem or CLI imports. CRC64 is explicitly disabled
// in this synthetic format-11 snapshot containing one String key.
fn main raise {
  let snapshot = @moonrdb.parse(
    b"REDIS0011\x00\x01k\x01v\xff\x00\x00\x00\x00\x00\x00\x00\x00",
  )
  guard snapshot.records[0] is String(record) else { fail("expected String") }
  println("db=\{record.database}, value_matches=\{record.value == b"v"}")
  println("checksum_disabled=\{snapshot.checksum is Disabled}")
}
