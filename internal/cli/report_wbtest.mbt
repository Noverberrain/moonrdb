// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn inspect_body(body : Bytes) -> String raise {
  inspect_report(
    @moonrdb.parse(
      b"REDIS0011" + body + b"\xff\x00\x00\x00\x00\x00\x00\x00\x00",
    ),
  )
}

///|
test "inspect reports selected empty databases sorted and deduplicated" {
  let text = inspect_body(b"\xfe\x02\xfe\x00\xfe\x02")
  assert_true(text.contains("databases: 2\ndb 0: keys=0\ndb 2: keys=0\n"))
  assert_true(
    text.contains(
      "checksum: disabled (CRC64 not validated)\nstatus: complete\n",
    ),
  )
  assert_true(inspect_body(b"").contains("databases: 0\n"))
}

///|
test "inspect accounts implicit database zero and prints no binary key or AUX" {
  let text = inspect_body(
    b"\xfa\x02\x1bX\x01v\x00\x03\x1b\x00\xff\x01v\xfe\x02\x02\x00\x01\x01s",
  )
  assert_true(
    text.contains(
      "keys: 2\naux_fields: 1\ndatabases: 2\ndb 0: keys=1\ndb 2: keys=1\n",
    ),
  )
  assert_false(text.contains("\u001b"))
}

///|
async test "real valid checksum appears only after full parse" {
  let input = @fs.read_binary(
    "fixtures/redis-7.2.5-sorted-sets/sorted-sets.rdb",
  )
  let text = inspect_report(@moonrdb.parse(input))
  assert_true(text.contains("format_version: 11\nfile_bytes: 486\nkeys: 8\n"))
  assert_true(
    text.contains(
      "db 0: keys=5\ndb 2: keys=3\nchecksum: valid (CRC64)\nstatus: complete\n",
    ),
  )
}
