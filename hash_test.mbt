// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn hash_error(
  input : Bytes,
  max_hash_entries~ : Int32 = 100000,
  max_string_bytes~ : Int32 = 1024 * 1024,
  max_packed_bytes~ : Int32 = 4 * 1024 * 1024,
  max_decoded_bytes~ : Int32 = 64 * 1024 * 1024,
) -> @moonrdb.ParseError raise {
  try
    @moonrdb.parse(
      input,
      max_hash_entries~,
      max_string_bytes~,
      max_packed_bytes~,
      max_decoded_bytes~,
    )
  catch {
    error => error
  } noraise {
    _ => fail("expected Hash parse failure")
  }
}

///|
fn only_hash(input : Bytes) -> @moonrdb.HashRecord raise {
  let result = @moonrdb.parse(input)
  assert_eq(result.records.length(), 1)
  guard result.records[0] is Hash(record) else { fail("expected Hash record") }
  record
}

///|
test "packed Hash scratch and semantic budgets are bounded separately" {
  let blob = b"\x0f\x00\x00\x00\x02\x00\x81f\x02\x83abc\x04\xff"
  let input = empty_file(b"\x10\x00\x0f" + blob)
  let result = @moonrdb.parse(
    input,
    max_string_bytes=3,
    max_packed_bytes=15,
    max_decoded_bytes=4,
  )
  guard result.records[0] is Hash(record) else { fail("expected packed Hash") }
  assert_eq(record.entries[0].value, b"abc")
  assert_true(record.packed_storage is Some(Raw))
  assert_true(
    hash_error(input, max_packed_bytes=14)
    is ResourceLimitExceeded(resource="packed-bytes", actual=15UL, ..),
  )
  assert_true(
    hash_error(input, max_string_bytes=2)
    is ResourceLimitExceeded(resource="string-bytes", actual=3UL, ..),
  )
  assert_true(
    hash_error(input, max_decoded_bytes=3)
    is ResourceLimitExceeded(resource="decoded-bytes", actual=4UL, ..),
  )
  assert_true(
    hash_error(input, max_hash_entries=0)
    is ResourceLimitExceeded(resource="hash-entries", ..),
  )
}

///|
test "compressed packed Hash validates scratch limit and reports decoded inner offsets" {
  let blob = b"\x0f\x00\x00\x00\x02\x00\x81f\x02\x83abc\x04\xff"
  let input = empty_file(b"\x10\x00\xc3\x10\x0f\x0e" + blob)
  let result = @moonrdb.parse(
    input,
    max_string_bytes=3,
    max_packed_bytes=15,
    max_decoded_bytes=4,
  )
  guard result.records[0] is Hash(record) else {
    fail("expected compressed packed Hash")
  }
  assert_true(record.packed_storage is Some(Lzf))
  assert_eq(record.entries[0].value, b"abc")
  assert_true(
    hash_error(input, max_packed_bytes=14)
    is ResourceLimitExceeded(resource="packed-bytes", actual=15UL, ..),
  )
  let bad_blob = Bytes::makei(blob.length(), i => {
    if i == 8 {
      0
    } else {
      blob[i]
    }
  })
  assert_true(
    hash_error(empty_file(b"\x10\x00\xc3\x10\x0f\x0e" + bad_blob))
    is InvalidListpack(offset=11, inner_offset=8, ..),
  )
}

///|
test "Hash members and String records share the cumulative decoded-byte budget" {
  let input = empty_file(b"\x04\x00\x01\x01f\x01v\x00\x00\x02zz")
  assert_eq(@moonrdb.parse(input, max_decoded_bytes=4).records.length(), 2)
  assert_true(
    hash_error(input, max_decoded_bytes=3)
    is ResourceLimitExceeded(resource="decoded-bytes", actual=4UL, ..),
  )
}

///|
test "ordinary Hash handles binary empty and integer encoded fields and values" {
  let record = only_hash(
    empty_file(b"\x04\x01k\x02\x02\x00\xff\x00\xc0\xff\xc2\x00\x00\x00\x80"),
  )
  assert_true(record.storage is Hashtable)
  assert_eq(record.packed_storage, None)
  assert_eq(record.entries[0].field, b"\x00\xff")
  assert_eq(record.entries[0].value, b"")
  assert_eq(record.entries[1].field, b"-1")
  assert_eq(record.entries[1].value, b"-2147483648")
}

///|
test "ordinary Hash rejects huge counts duplicates empty hashes and encoded counts" {
  assert_true(
    hash_error(empty_file(b"\x04\x00\x81\xff\xff\xff\xff\xff\xff\xff\xff"))
    is ResourceLimitExceeded(
      resource="hash-entries",
      actual=0xffffffffffffffffUL,
      ..
    ),
  )
  assert_true(
    hash_error(empty_file(b"\x04\x00\x00"))
    is InvalidHash(reason="empty hash", ..),
  )
  assert_true(
    hash_error(empty_file(b"\x04\x00\xc0")) is UnexpectedEncodedLength(..),
  )
  assert_true(
    hash_error(empty_file(b"\x04\x00\x02\x01f\x01a\x01f\x01b"))
    is InvalidHash(reason="duplicate field", ..),
  )
  assert_true(
    hash_error(empty_file(b"\x04\x00\x01\x01f\x01v"), max_hash_entries=0)
    is ResourceLimitExceeded(resource="hash-entries", ..),
  )
}

///|
test "generic parser preserves narrow API boundaries and rejects legacy Hash formats" {
  let input = empty_file(b"\x04\x00\x01\x01f\x01v")
  assert_true(
    strings_error(input) is UnsupportedObjectType(object_type=b'\x04', ..),
  )
  assert_true(
    empty_error(input) is UnsupportedObjectType(object_type=b'\x04', ..),
  )
  for value in [9, 13, 1, 2, 5] {
    assert_true(
      hash_error(empty_file(([value.to_byte()] : Bytes)))
      is UnsupportedObjectType(..),
    )
  }
  assert_true(
    hash_error(input, max_hash_entries=-1)
    is InvalidResourceLimit(resource="hash-entries", ..),
  )
  assert_true(
    hash_error(input, max_packed_bytes=-1)
    is InvalidResourceLimit(resource="packed-bytes", ..),
  )
}

///|
async test "real mixed Hash snapshot verifies both encodings and persisted semantic pairs" {
  let input = @fs.read_binary("fixtures/redis-7.2.5-hashes/hashes.rdb")
  let result = @moonrdb.parse(input)
  assert_eq(result.records.length(), 9)
  assert_eq(result.database_selections, [0UL, 2UL])
  assert_true(result.checksum is Valid(_))
  let cases : Array[(UInt64, Bytes, Array[(Bytes, Bytes)])] = [
    (
      0UL,
      b"compact",
      [
        (b"name", b"alice"),
        (b"age", b"42"),
        (b"\x00\xff", b"\x80\x00"),
        (b"", b""),
      ],
    ),
    (
      0UL,
      b"count-overflow",
      [
        (b"f0", b"v0"),
        (b"f1", b"v1"),
        (b"f2", b"v2"),
        (b"f3", b"v3"),
        (b"f4", b"v4"),
      ],
    ),
    (0UL, b"long-value", [(b"payload", b"x".repeat(1000))]),
    (0UL, b"long-field", [(b"f".repeat(65), b"v")]),
    (0UL, b"key:" + b"K".repeat(1024), [(b"f", b"v")]),
    (
      2UL,
      b"ints",
      [
        (b"-4096", b"4095"),
        (b"-32768", b"32767"),
        (b"-8388608", b"8388607"),
        (b"-9223372036854775808", b"9223372036854775807"),
      ],
    ),
    (2UL, b"ints2", [(b"-2147483648", b"2147483647"), (b"127", b"128")]),
    (
      2UL,
      b"packed-lzf",
      [
        (b"f0", b"a".repeat(60)),
        (b"f1", b"b".repeat(60)),
        (b"f2", b"c".repeat(60)),
        (b"f3", b"d".repeat(60)),
      ],
    ),
  ]
  for (db, key, expected) in cases {
    let hashes = result.records.filter(record => {
      match record {
        Hash(value) => value.database == db && value.key == key
        _ => false
      }
    })
    assert_eq(hashes.length(), 1)
    guard hashes[0] is Hash(record) else { fail("expected Hash") }
    assert_eq(record.entries.length(), expected.length())
    for (field, value) in expected {
      let pairs = record.entries.filter(entry => entry.field == field)
      assert_eq(pairs.length(), 1)
      assert_eq(pairs[0].value, value)
    }
    assert_true(record.frequency is Some(_))
    assert_eq(record.idle_seconds, None)
    if key == b"ints" {
      assert_eq(record.expires_at_ms, Some(4102444800123L))
    } else {
      assert_eq(record.expires_at_ms, None)
    }
    if key == b"count-overflow" || key == b"long-value" || key == b"long-field" {
      assert_true(record.storage is Hashtable)
    } else {
      assert_true(record.storage is Listpack)
    }
    if key == b"packed-lzf" {
      assert_true(record.packed_storage is Some(Lzf))
    }
    if key.length() > 1000 {
      assert_true(record.key_storage is Lzf)
    }
  }
  let mut total = result.global_overhead_bytes
  let mut previous_end = 9
  let mut strings = 0
  for record in result.records {
    let (start, end, size) = match record {
      List(_) => fail("unexpected List in Hash fixture")
      Hash(value) =>
        (value.record_start, value.record_end, value.serialized_bytes)
      String(value) => {
        strings += 1
        assert_eq(value.key, b"marker")
        assert_eq(value.value, b"mixed")
        (value.record_start, value.record_end, value.serialized_bytes)
      }
    }
    assert_true(start >= previous_end && end > start)
    assert_eq(size, (end - start).to_uint64())
    previous_end = end
    total += size
  }
  assert_eq(strings, 1)
  assert_eq(total, input.length().to_uint64())
}

///|
async test "all real Hash file truncations and single-bit mutations fail" {
  let input = @fs.read_binary("fixtures/redis-7.2.5-hashes/hashes.rdb")
  for size in 0..<input.length() {
    ignore(hash_error(input[:size].to_owned()))
  }
  for offset in 0..<input.length() {
    let bad = Bytes::makei(input.length(), i => {
      if i == offset {
        (input[i].to_int() ^ 1).to_byte()
      } else {
        input[i]
      }
    })
    ignore(hash_error(bad))
  }
}

///|
async test "generic parser retains the three previous real fixture semantics" {
  for
    path in [
      "redis-7.2.5/empty.rdb", "redis-7.2.5-no-checksum/empty.rdb", "redis-7.2.5-strings/strings.rdb",
    ] {
    let input = @fs.read_binary("fixtures/\{path}")
    let result = @moonrdb.parse(input)
    let narrow = @moonrdb.parse_strings(input)
    assert_eq(result.records.length(), narrow.records.length())
    for i in 0..<result.records.length() {
      guard result.records[i] is String(value) else { fail("unexpected Hash") }
      assert_eq(value, narrow.records[i])
    }
    assert_eq(result.checksum, narrow.checksum)
  }
}
