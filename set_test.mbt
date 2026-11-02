// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn set_error(
  input : Bytes,
  max_set_members~ : Int32 = 100000,
  max_string_bytes~ : Int32 = 1024 * 1024,
  max_packed_bytes~ : Int32 = 4 * 1024 * 1024,
  max_decoded_bytes~ : Int32 = 64 * 1024 * 1024,
) -> @moonrdb.ParseError raise {
  try
    @moonrdb.parse(
      input,
      max_set_members~,
      max_string_bytes~,
      max_packed_bytes~,
      max_decoded_bytes~,
    )
  catch {
    error => error
  } noraise {
    _ => fail("expected Set parse failure")
  }
}

///|
fn only_set(input : Bytes) -> @moonrdb.SetRecord raise {
  let result = @moonrdb.parse(input)
  assert_eq(result.records.length(), 1)
  guard result.records[0] is Set(record) else { fail("expected Set record") }
  record
}

///|
test "ordinary Set preserves binary empty and exact numeric text" {
  let record = only_set(
    empty_file(b"\x02\x00\x04\x02\x00\xff\x00\xc0\x01\x02" + b"01"),
  )
  assert_eq(record.members, [b"\x00\xff", b"", b"1", b"01"])
  assert_true(record.storage is Hashtable)
  assert_eq(record.packed_storage, None)
}

///|
test "ordinary Set duplicates empty counts and encoded counts fail closed" {
  assert_true(
    set_error(empty_file(b"\x02\x00\x02\xc0\x01\x01" + b"1"))
    is InvalidSet(reason="duplicate member", ..),
  )
  assert_true(
    set_error(empty_file(b"\x02\x00\x02\x00\x00"))
    is InvalidSet(reason="duplicate member", ..),
  )
  assert_true(
    set_error(empty_file(b"\x02\x00\x00")) is InvalidSet(reason="empty set", ..),
  )
  assert_true(
    set_error(empty_file(b"\x02\x00\xc0")) is UnexpectedEncodedLength(..),
  )
  assert_true(
    set_error(empty_file(b"\x02\x00\x81\xff\xff\xff\xff\xff\xff\xff\xff"))
    is ResourceLimitExceeded(
      resource="set-members",
      actual=0xffffffffffffffffUL,
      ..
    ),
  )
}

///|
test "Set member budget is global and cannot wrap after earlier records" {
  let input = empty_file(b"\x02\x00\x01\x01a\x02\x00\x01\x01a")
  assert_eq(@moonrdb.parse(input, max_set_members=2).records.length(), 2)
  assert_true(
    set_error(input, max_set_members=1)
    is ResourceLimitExceeded(resource="set-members", actual=2UL, ..),
  )
  let huge = empty_file(
    b"\x02\x00\x01\x01a\x02\x00\x81\xff\xff\xff\xff\xff\xff\xff\xff",
  )
  assert_true(
    set_error(huge)
    is ResourceLimitExceeded(
      resource="set-members",
      actual=0xffffffffffffffffUL,
      ..
    ),
  )
  assert_true(
    set_error(input, max_set_members=-1)
    is InvalidResourceLimit(resource="set-members", ..),
  )
  assert_eq(
    @moonrdb.parse(empty_file(b"\x00\x00\x01s"), max_set_members=0).records.length(),
    1,
  )
}

///|
test "empty member consumes cardinality even with zero decoded bytes" {
  let input = empty_file(b"\x02\x00\x01\x00")
  assert_eq(
    @moonrdb.parse(
      input,
      max_set_members=1,
      max_string_bytes=0,
      max_decoded_bytes=0,
    ).records.length(),
    1,
  )
  assert_true(
    set_error(input, max_set_members=0)
    is ResourceLimitExceeded(resource="set-members", actual=1UL, ..),
  )
}

///|
test "intset and listpack scratch do not consume logical result budget twice" {
  let intset = b"\x02\x00\x00\x00\x02\x00\x00\x00\x01\x00\x02\x00"
  let input = empty_file(b"\x0b\x00\x0c" + intset)
  assert_eq(
    @moonrdb.parse(
      input,
      max_string_bytes=1,
      max_packed_bytes=12,
      max_decoded_bytes=2,
    ).records.length(),
    1,
  )
  assert_true(
    set_error(input, max_packed_bytes=11)
    is ResourceLimitExceeded(resource="packed-bytes", actual=12UL, ..),
  )
  assert_true(
    set_error(input, max_decoded_bytes=1)
    is ResourceLimitExceeded(resource="decoded-bytes", actual=2UL, ..),
  )
  let blob = b"\x10\x00\x00\x00\x03\x00\x01\x01\x83raw\x04\x80\x01\xff"
  let packed = empty_file(b"\x14\x00\x10" + blob)
  assert_eq(
    @moonrdb.parse(
      packed,
      max_string_bytes=3,
      max_packed_bytes=16,
      max_decoded_bytes=4,
    ).records.length(),
    1,
  )
  assert_true(
    set_error(packed, max_packed_bytes=15)
    is ResourceLimitExceeded(resource="packed-bytes", actual=16UL, ..),
  )
  assert_true(
    set_error(packed, max_decoded_bytes=3)
    is ResourceLimitExceeded(resource="decoded-bytes", actual=4UL, ..),
  )
}

///|
test "compressed intset retains storage and reports decoded inner offsets" {
  let blob = b"\x02\x00\x00\x00\x02\x00\x00\x00\x01\x00\x02\x00"
  let record = only_set(empty_file(b"\x0b\x00\xc3\x0d\x0c\x0b" + blob))
  assert_eq(record.members, [b"1", b"2"])
  assert_true(record.storage is Intset(2))
  assert_true(record.packed_storage is Some(Lzf))
  let bad = Bytes::makei(blob.length(), i => if i == 10 { 1 } else { blob[i] })
  assert_true(
    set_error(empty_file(b"\x0b\x00\xc3\x0d\x0c\x0b" + bad))
    is InvalidIntset(
      offset=11,
      inner_offset=10,
      reason="members not strictly increasing"
    ),
  )
  assert_true(
    set_error(
      empty_file(b"\x0b\x00\xc3\x00\x81\xff\xff\xff\xff\xff\xff\xff\xff"),
    )
    is ResourceLimitExceeded(
      resource="packed-bytes",
      actual=0xffffffffffffffffUL,
      ..
    ),
  )
}

///|
test "Set listpack accepts odd counts but rejects duplicates and dishonest counts" {
  let blob = b"\x10\x00\x00\x00\xff\xff\x01\x01\x83raw\x04\x80\x01\xff"
  let input = empty_file(b"\x14\x00\x10" + blob)
  assert_eq(only_set(input).members, [b"1", b"raw", b""])
  assert_true(
    set_error(input, max_set_members=2)
    is ResourceLimitExceeded(resource="set-members", actual=3UL, ..),
  )
  let duplicate = b"\x0c\x00\x00\x00\x02\x00\x01\x01\x81" + b"1" + b"\x02\xff"
  assert_true(
    set_error(empty_file(b"\x14\x00\x0c" + duplicate))
    is InvalidSet(reason="duplicate member", ..),
  )
  let dishonest = Bytes::makei(blob.length(), i => {
    if i == 4 {
      2
    } else if i == 5 {
      0
    } else {
      blob[i]
    }
  })
  assert_true(
    set_error(empty_file(b"\x14\x00\x10" + dishonest))
    is InvalidListpack(inner_offset=4, ..),
  )
  assert_true(
    set_error(empty_file(b"\x14\x00\x07\x07\x00\x00\x00\x00\x00\xff"))
    is InvalidSet(reason="empty set", ..),
  )
}

///|
test "Set retains absolute metadata and accounts for the original record interval" {
  let body = b"\xfc\x00\x00\x00\x00\x00\x00\x00\x00\xf9\xff\x02\x01k\x01\x01v"
  let result = @moonrdb.parse(empty_file(body))
  guard result.records[0] is Set(record) else { fail("expected Set") }
  assert_eq(record.expires_at_ms, Some(0L))
  assert_eq(record.frequency, Some(b'\xff'))
  assert_eq(record.record_start, 9)
  assert_eq(record.record_end, 9 + body.length())
  assert_eq(record.serialized_bytes, body.length().to_uint64())
  assert_eq(result.global_overhead_bytes, 18UL)
  assert_true(
    strings_error(empty_file(b"\x02\x00\x01\x01v"))
    is UnsupportedObjectType(object_type=b'\x02', ..),
  )
  assert_true(
    empty_error(empty_file(b"\x02\x00\x01\x01v"))
    is UnsupportedObjectType(object_type=b'\x02', ..),
  )
}

///|
test "member budgets span ordinary intset and known or unknown listpack counts" {
  let prefix = b"\x02\x00\x01\x01a"
  let bodies = [
    b"\x0b\x00\x0c\x02\x00\x00\x00\x02\x00\x00\x00\x01\x00\x02\x00", b"\x14\x00\x0b\x0b\x00\x00\x00\x02\x00\x01\x01\x02\x01\xff",
    b"\x14\x00\x0b\x0b\x00\x00\x00\xff\xff\x01\x01\x02\x01\xff",
  ]
  for body in bodies {
    let input = empty_file(prefix + body)
    assert_eq(@moonrdb.parse(input, max_set_members=3).records.length(), 2)
    assert_true(
      set_error(input, max_set_members=2)
      is ResourceLimitExceeded(resource="set-members", actual=3UL, ..),
    )
  }
}

///|
test "Set shares decoded bytes with other types and leaves historical encodings unsupported" {
  let input = empty_file(b"\x02\x00\x01\x01a\x00\x00\x02zz")
  assert_eq(@moonrdb.parse(input, max_decoded_bytes=3).records.length(), 2)
  assert_true(
    set_error(input, max_decoded_bytes=2)
    is ResourceLimitExceeded(resource="decoded-bytes", actual=3UL, ..),
  )
  for code in [3, 12, 21] {
    assert_true(
      set_error(empty_file(([code.to_byte()] : Bytes)))
      is UnsupportedObjectType(..),
    )
  }
}

///|
async test "real Set fixture covers three encodings widths and unordered semantics" {
  let input = @fs.read_binary("fixtures/redis-7.2.5-sets/sets.rdb")
  let result = @moonrdb.parse(input, max_set_members=36)
  assert_eq(result.records.length(), 13)
  assert_eq(result.database_selections, [0UL, 2UL])
  assert_true(result.checksum is Valid(_))
  let cases : Array[(UInt64, Bytes, Array[Bytes])] = [
    (0UL, b"int16", [b"-32768", b"-1", b"0", b"32767"]),
    (0UL, b"int32", [b"-2147483648", b"0", b"2147483647"]),
    (2UL, b"int64", [b"-9223372036854775808", b"0", b"9223372036854775807"]),
    (0UL, b"compact", [b"alpha", b"", b"\x00\xff", b"00123"]),
    (0UL, b"mixed-int", [b"alpha", b"42", b"-128", b"9223372036854775807"]),
    (0UL, b"overflow", [b"v0", b"v1", b"v2", b"v3", b"v4"]),
    (0UL, b"ints-overflow", [b"0", b"1", b"2", b"3", b"4"]),
    (0UL, b"long-value", [b"x".repeat(1000), b"short"]),
    (
      2UL,
      b"packed-lzf",
      [b"a".repeat(60), b"b".repeat(60), b"c".repeat(60), b"d".repeat(60)],
    ),
    (2UL, b"set:" + b"K".repeat(1024), [b"value", b"42"]),
  ]
  for (db, key, expected) in cases {
    let matches = result.records.filter(record => {
      match record {
        Set(value) => value.database == db && value.key == key
        _ => false
      }
    })
    assert_eq(matches.length(), 1)
    guard matches[0] is Set(record) else { fail("expected Set") }
    assert_eq(record.members.length(), expected.length())
    for value in expected {
      assert_eq(record.members.filter(actual => actual == value).length(), 1)
    }
    assert_true(record.frequency is Some(_))
    assert_eq(record.idle_seconds, None)
    if key == b"int64" {
      assert_eq(record.expires_at_ms, Some(4102444800123L))
    } else {
      assert_eq(record.expires_at_ms, None)
    }
    if key == b"int16" {
      assert_true(record.storage is Intset(2))
    } else if key == b"int32" {
      assert_true(record.storage is Intset(4))
    } else if key == b"int64" {
      assert_true(record.storage is Intset(8))
    } else if key == b"overflow" ||
      key == b"ints-overflow" ||
      key == b"long-value" {
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
  assert_true(
    set_error(input, max_set_members=35)
    is ResourceLimitExceeded(resource="set-members", actual=36UL, ..),
  )
  let mut total = result.global_overhead_bytes
  let mut previous_end = 9
  let mut markers = 0
  for record in result.records {
    let (start, end, size) = match record {
      SortedSet(_) => fail("unexpected Sorted Set")
      Set(value) =>
        (value.record_start, value.record_end, value.serialized_bytes)
      String(value) => {
        markers += 1
        assert_eq(value.value, b"mixed")
        (value.record_start, value.record_end, value.serialized_bytes)
      }
      Hash(value) => {
        markers += 1
        assert_eq(value.entries[0].value, b"v")
        (value.record_start, value.record_end, value.serialized_bytes)
      }
      List(value) => {
        markers += 1
        assert_eq(value.items, [b"left", b"right"])
        (value.record_start, value.record_end, value.serialized_bytes)
      }
    }
    assert_true(start >= previous_end && end > start)
    assert_eq(size, (end - start).to_uint64())
    previous_end = end
    total += size
  }
  assert_eq(markers, 3)
  assert_eq(total, input.length().to_uint64())
}

///|
async test "all real Set short prefixes and single-bit mutations fail" {
  let input = @fs.read_binary("fixtures/redis-7.2.5-sets/sets.rdb")
  for length in 0..<input.length() {
    ignore(set_error(input[:length].to_owned()))
  }
  for offset in 0..<input.length() {
    let bad = Bytes::makei(input.length(), i => {
      if i == offset {
        (input[i].to_int() ^ 1).to_byte()
      } else {
        input[i]
      }
    })
    ignore(set_error(bad))
  }
}
