// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn zset_error(
  input : Bytes,
  max_sorted_set_entries~ : Int32 = 100000,
  max_decoded_bytes~ : Int32 = 67108864,
  max_packed_bytes~ : Int32 = 4194304,
  max_string_bytes~ : Int32 = 1048576,
) -> @moonrdb.ParseError raise {
  try
    @moonrdb.parse(
      input,
      max_sorted_set_entries~,
      max_decoded_bytes~,
      max_packed_bytes~,
      max_string_bytes~,
    )
  catch {
    error => error
  } noraise {
    _ => fail("expected Sorted Set failure")
  }
}

///|
fn only_zset(body : Bytes) -> @moonrdb.SortedSetRecord raise {
  let result = @moonrdb.parse(empty_file(body))
  assert_eq(result.records.length(), 1)
  guard result.records[0] is SortedSet(record) else {
    fail("expected Sorted Set")
  }
  record
}

///|
test "binary scores preserve IEEE bits and wire order" {
  let r = only_zset(
    b"\x05\x00\x05\x01\x61\x00\x00\x00\x00\x00\x00\xf0\x7f\x00\x00\x00\x00\x00\x00\x00\x00\x80\x02\x00\xff\x01\x00\x00\x00\x00\x00\x00\x00\x03\x74\x69\x65\x00\x00\x00\x00\x00\x00\xf4\x3f\x08\x6e\x65\x67\x61\x74\x69\x76\x65\x00\x00\x00\x00\x00\x00\xf0\xff",
  )
  assert_true(r.storage is BinaryDouble)
  assert_eq(r.packed_storage, None)
  assert_eq(r.entries.length(), 5)
  assert_eq(r.entries[1].score.reinterpret_as_uint64(), 0x8000000000000000UL)
  assert_eq(r.entries[2].score.reinterpret_as_uint64(), 1UL)
  assert_eq(r.entries[2].element, b"\x00\xff")
  assert_true(r.entries[0].score.is_pos_inf())
  assert_true(r.entries[4].score.is_neg_inf())
}

///|
test "reject NaN" {
  assert_true(
    zset_error(
      empty_file(b"\x05\x00\x01\x01\x61\x00\x00\x00\x00\x00\x00\xf8\x7f"),
    )
    is InvalidSortedSet(..),
  )
}

///|
test "reject duplicate" {
  assert_true(
    zset_error(
      empty_file(
        b"\x05\x00\x02\x01\x61\x00\x00\x00\x00\x00\x00\xf0\x3f\x01\x61\x00\x00\x00\x00\x00\x00\x00\x40",
      ),
    )
    is InvalidSortedSet(..),
  )
}

///|
test "reject empty" {
  assert_true(zset_error(empty_file(b"\x05\x00\x00")) is InvalidSortedSet(..))
}

///|
test "reject odd pair" {
  assert_true(
    zset_error(
      empty_file(b"\x11\x00\x0a\x0a\x00\x00\x00\x01\x00\x81\x61\x02\xff"),
    )
    is InvalidSortedSet(..),
  )
}

///|
test "reject duplicate packed" {
  assert_true(
    zset_error(
      empty_file(
        b"\x11\x00\x11\x11\x00\x00\x00\x04\x00\x81\x61\x02\x01\x01\x81\x61\x02\x02\x01\xff",
      ),
    )
    is InvalidSortedSet(..),
  )
}

///|
test "reject descending score" {
  assert_true(
    zset_error(
      empty_file(
        b"\x11\x00\x11\x11\x00\x00\x00\x04\x00\x81\x61\x02\x02\x01\x81\x62\x02\x01\x01\xff",
      ),
    )
    is InvalidSortedSet(..),
  )
}

///|
test "reject descending tie" {
  assert_true(
    zset_error(
      empty_file(
        b"\x11\x00\x11\x11\x00\x00\x00\x04\x00\x81\x62\x02\x01\x01\x81\x61\x02\x01\x01\xff",
      ),
    )
    is InvalidSortedSet(..),
  )
}

///|
test "reject empty packed" {
  assert_true(
    zset_error(empty_file(b"\x11\x00\x07\x07\x00\x00\x00\x00\x00\xff"))
    is InvalidSortedSet(..),
  )
}

///|
test "reject packed score 6.0e616e" {
  assert_true(
    zset_error(
      empty_file(
        b"\x11\x00\x0f\x0f\x00\x00\x00\x02\x00\x81\x61\x02\x83\x6e\x61\x6e\x04\xff",
      ),
    )
    is InvalidSortedSet(..),
  )
}

///|
test "reject packed score 315f30" {
  assert_true(
    zset_error(
      empty_file(
        b"\x11\x00\x0f\x0f\x00\x00\x00\x02\x00\x81\x61\x02\x83\x31\x5f\x30\x04\xff",
      ),
    )
    is InvalidSortedSet(..),
  )
}

///|
test "reject packed score 2031" {
  assert_true(
    zset_error(
      empty_file(
        b"\x11\x00\x0e\x0e\x00\x00\x00\x02\x00\x81\x61\x02\x82\x20\x31\x03\xff",
      ),
    )
    is InvalidSortedSet(..),
  )
}

///|
test "reject packed score 3100" {
  assert_true(
    zset_error(
      empty_file(
        b"\x11\x00\x0e\x0e\x00\x00\x00\x02\x00\x81\x61\x02\x82\x31\x00\x03\xff",
      ),
    )
    is InvalidSortedSet(..),
  )
}

///|
test "reject packed score 3165393939" {
  assert_true(
    zset_error(
      empty_file(
        b"\x11\x00\x11\x11\x00\x00\x00\x02\x00\x81\x61\x02\x85\x31\x65\x39\x39\x39\x06\xff",
      ),
    )
    is InvalidSortedSet(..),
  )
}

///|
test "reject packed score " {
  assert_true(
    zset_error(
      empty_file(
        b"\x11\x00\x0c\x0c\x00\x00\x00\x02\x00\x81\x61\x02\x80\x01\xff",
      ),
    )
    is InvalidSortedSet(..),
  )
}

///|
test "reject packed score 6531" {
  assert_true(
    zset_error(
      empty_file(
        b"\x11\x00\x0e\x0e\x00\x00\x00\x02\x00\x81\x61\x02\x82\x65\x31\x03\xff",
      ),
    )
    is InvalidSortedSet(..),
  )
}

///|
test "reject packed score 2d2d31" {
  assert_true(
    zset_error(
      empty_file(
        b"\x11\x00\x0f\x0f\x00\x00\x00\x02\x00\x81\x61\x02\x83\x2d\x2d\x31\x04\xff",
      ),
    )
    is InvalidSortedSet(..),
  )
}

///|
test "packed integer decimal exponent scores and unknown count" {
  let r = only_zset(
    b"\x11\x00\x20\x20\x00\x00\x00\xff\xff\x81\x61\x02\x85\x2d\x31\x2e\x32\x35\x06\x81\x62\x02\x00\x01\x81\x63\x02\x85\x31\x65\x31\x30\x30\x06\xff",
  )
  assert_true(r.storage is Listpack)
  assert_eq(r.entries.map(e => e.score), [-1.25, 0.0, 1.0e100])
}

///|
test "entry limits global no wrap and zero byte member counts" {
  let body = b"\x05\x00\x01\x00\x00\x00\x00\x00\x00\x00\xf0\x3f"
  assert_eq(
    @moonrdb.parse(empty_file(body), max_decoded_bytes=0, max_string_bytes=0).records.length(),
    1,
  )
  assert_eq(
    @moonrdb.parse(empty_file(body + body), max_sorted_set_entries=2).records.length(),
    2,
  )
  assert_true(
    zset_error(empty_file(body + body), max_sorted_set_entries=1)
    is ResourceLimitExceeded(resource="sorted-set-entries", actual=2UL, ..),
  )
  assert_true(
    zset_error(empty_file(body), max_sorted_set_entries=-1)
    is InvalidResourceLimit(resource="sorted-set-entries", ..),
  )
  assert_true(
    zset_error(
      empty_file(body + b"\x05\x00\x81\xff\xff\xff\xff\xff\xff\xff\xff"),
    )
    is ResourceLimitExceeded(
      resource="sorted-set-entries",
      actual=0xffffffffffffffffUL,
      ..
    ),
  )
}

///|
test "logical member budget separate from score and packed scratch" {
  let input = empty_file(
    b"\x11\x00\x10\x10\x00\x00\x00\x02\x00\x81\x61\x02\x84\x31\x2e\x32\x35\x05\xff",
  )
  assert_eq(
    @moonrdb.parse(
      input,
      max_decoded_bytes=1,
      max_string_bytes=1,
      max_packed_bytes=16,
    ).records.length(),
    1,
  )
  assert_true(
    zset_error(input, max_decoded_bytes=0)
    is ResourceLimitExceeded(resource="decoded-bytes", ..),
  )
  assert_true(
    zset_error(input, max_packed_bytes=15)
    is ResourceLimitExceeded(resource="packed-bytes", ..),
  )
  assert_true(
    zset_error(input, max_string_bytes=0)
    is ResourceLimitExceeded(resource="string-bytes", ..),
  )
}

///|
test "bad packed counts and global mixed representation budget" {
  assert_true(
    zset_error(
      empty_file(
        b"\x11\x00\x0c\x0c\x00\x00\x00\x04\x00\x81\x61\x02\x01\x01\xff",
      ),
    )
    is InvalidListpack(..),
  )
  assert_true(
    zset_error(
      empty_file(
        b"\x05\x00\x01\x00\x00\x00\x00\x00\x00\x00\xf0\x3f\x11\x00\x0c\x0c\x00\x00\x00\x02\x00\x81\x61\x02\x01\x01\xff",
      ),
      max_sorted_set_entries=1,
    )
    is ResourceLimitExceeded(resource="sorted-set-entries", ..),
  )
}

///|
async test "real Sorted Set fixture semantics encodings metadata and accounting" {
  let input = @fs.read_binary(
    "fixtures/redis-7.2.5-sorted-sets/sorted-sets.rdb",
  )
  let result = @moonrdb.parse(input, max_sorted_set_entries=20)
  assert_true(result.checksum is Valid(_))
  assert_eq(result.records.length(), 8)
  let mut total = result.global_overhead_bytes
  let mut previous_end = 9
  for record in result.records {
    let (start, end, size) = match record {
      SortedSet(r) => (r.record_start, r.record_end, r.serialized_bytes)
      Set(r) => {
        assert_eq(r.members, [b"value"])
        (r.record_start, r.record_end, r.serialized_bytes)
      }
      String(r) => {
        assert_eq(r.value, b"mixed")
        (r.record_start, r.record_end, r.serialized_bytes)
      }
      _ => fail("unexpected type")
    }
    assert_true(start >= previous_end && end > start)
    assert_eq(size, (end - start).to_uint64())
    total += size
    previous_end = end
  }
  assert_eq(total, input.length().to_uint64())
  {
    let matches = result.records.filter(record => {
      match record {
        SortedSet(r) =>
          r.database == 0UL && r.key == b"\x63\x6f\x6d\x70\x61\x63\x74"
        _ => false
      }
    })
    assert_eq(matches.length(), 1)
    guard matches[0] is SortedSet(r) else { fail("expected Sorted Set") }
    assert_eq(r.entries.length(), 4)
    assert_true(r.storage is Listpack)
    assert_true(r.frequency is Some(_))
    assert_eq(r.expires_at_ms, None)
    assert_eq(
      r.entries.filter(e => e.element == b"" && e.score.is_neg_inf()).length(),
      1,
    )
    assert_eq(
      r.entries
      .filter(e => e.element == b"\x00\xff" && e.score == -1.25)
      .length(),
      1,
    )
    assert_eq(
      r.entries.filter(e => e.element == b"\x34\x32" && e.score == 0.0).length(),
      1,
    )
    assert_eq(
      r.entries
      .filter(e => e.element == b"\x74\x61\x69\x6c" && e.score.is_pos_inf())
      .length(),
      1,
    )
  }
  {
    let matches = result.records.filter(record => {
      match record {
        SortedSet(r) => r.database == 0UL && r.key == b"\x74\x69\x65\x73"
        _ => false
      }
    })
    assert_eq(matches.length(), 1)
    guard matches[0] is SortedSet(r) else { fail("expected Sorted Set") }
    assert_eq(r.entries.length(), 3)
    assert_true(r.storage is Listpack)
    assert_true(r.frequency is Some(_))
    assert_eq(r.expires_at_ms, None)
    assert_eq(
      r.entries.filter(e => e.element == b"\x61" && e.score == 1.0).length(),
      1,
    )
    assert_eq(
      r.entries.filter(e => e.element == b"\x62" && e.score == 1.0).length(),
      1,
    )
    assert_eq(
      r.entries.filter(e => e.element == b"\x63" && e.score == 1.0).length(),
      1,
    )
  }
  {
    let matches = result.records.filter(record => {
      match record {
        SortedSet(r) =>
          r.database == 0UL && r.key == b"\x6f\x76\x65\x72\x66\x6c\x6f\x77"
        _ => false
      }
    })
    assert_eq(matches.length(), 1)
    guard matches[0] is SortedSet(r) else { fail("expected Sorted Set") }
    assert_eq(r.entries.length(), 5)
    assert_true(r.storage is BinaryDouble)
    assert_true(r.frequency is Some(_))
    assert_eq(r.expires_at_ms, None)
    assert_eq(
      r.entries
      .filter(e => e.element == b"\x76\x30" && e.score.is_neg_inf())
      .length(),
      1,
    )
    assert_eq(
      r.entries
      .filter(e => e.element == b"\x76\x31" && e.score == -1.25)
      .length(),
      1,
    )
    assert_eq(
      r.entries.filter(e => e.element == b"\x76\x32" && e.score == 0.0).length(),
      1,
    )
    assert_eq(
      r.entries
      .filter(e => {
        e.element == b"\x76\x33" && e.score == 1.7976931348623157e+308
      })
      .length(),
      1,
    )
    assert_eq(
      r.entries
      .filter(e => e.element == b"\x76\x34" && e.score.is_pos_inf())
      .length(),
      1,
    )
  }
  {
    let matches = result.records.filter(record => {
      match record {
        SortedSet(r) =>
          r.database == 2UL &&
          r.key == b"\x6c\x6f\x6e\x67\x2d\x6d\x65\x6d\x62\x65\x72"
        _ => false
      }
    })
    assert_eq(matches.length(), 1)
    guard matches[0] is SortedSet(r) else { fail("expected Sorted Set") }
    assert_eq(r.entries.length(), 2)
    assert_true(r.storage is BinaryDouble)
    assert_true(r.frequency is Some(_))
    assert_eq(r.expires_at_ms, Some(4102444800123L))
    assert_eq(
      r.entries
      .filter(e => e.element == b"L".repeat(1000) && e.score == 5.0e-324)
      .length(),
      1,
    )
    assert_eq(
      r.entries
      .filter(e => e.element == b"\x6f\x74\x68\x65\x72" && e.score == -0.0)
      .length(),
      1,
    )
  }
  {
    let matches = result.records.filter(record => {
      match record {
        SortedSet(r) =>
          r.database == 2UL &&
          r.key == b"\x70\x61\x63\x6b\x65\x64\x2d\x6c\x7a\x66"
        _ => false
      }
    })
    assert_eq(matches.length(), 1)
    guard matches[0] is SortedSet(r) else { fail("expected Sorted Set") }
    assert_eq(r.entries.length(), 4)
    assert_true(r.storage is Listpack)
    assert_true(r.frequency is Some(_))
    assert_eq(r.expires_at_ms, None)
    assert_true(r.packed_storage is Some(Lzf))
    assert_eq(
      r.entries
      .filter(e => e.element == b"a".repeat(60) && e.score == 0.0)
      .length(),
      1,
    )
    assert_eq(
      r.entries
      .filter(e => e.element == b"b".repeat(60) && e.score == 1.0)
      .length(),
      1,
    )
    assert_eq(
      r.entries
      .filter(e => e.element == b"c".repeat(60) && e.score == 2.0)
      .length(),
      1,
    )
    assert_eq(
      r.entries
      .filter(e => e.element == b"d".repeat(60) && e.score == 3.0)
      .length(),
      1,
    )
  }
  {
    let matches = result.records.filter(record => {
      match record {
        SortedSet(r) =>
          r.database == 2UL && r.key == b"zset:" + b"K".repeat(1024)
        _ => false
      }
    })
    assert_eq(matches.length(), 1)
    guard matches[0] is SortedSet(r) else { fail("expected Sorted Set") }
    assert_eq(r.entries.length(), 2)
    assert_true(r.storage is Listpack)
    assert_true(r.frequency is Some(_))
    assert_eq(r.expires_at_ms, None)
    assert_true(r.key_storage is Lzf)
    assert_eq(
      r.entries
      .filter(e => e.element == b"\x76\x61\x6c\x75\x65" && e.score == 0.1)
      .length(),
      1,
    )
    assert_eq(
      r.entries
      .filter(e => e.element == b"\x34\x32" && e.score == -2.0e+100)
      .length(),
      1,
    )
  }
  assert_true(
    zset_error(input, max_sorted_set_entries=19)
    is ResourceLimitExceeded(resource="sorted-set-entries", ..),
  )
}

///|
async test "all real Sorted Set prefixes and bit mutations fail" {
  let input = @fs.read_binary(
    "fixtures/redis-7.2.5-sorted-sets/sorted-sets.rdb",
  )
  for length in 0..<input.length() {
    ignore(zset_error(input[:length].to_owned()))
  }
  for offset in 0..<input.length() {
    let bad = Bytes::makei(input.length(), i => {
      if i == offset {
        (input[i].to_int() ^ 1).to_byte()
      } else {
        input[i]
      }
    })
    ignore(zset_error(bad))
  }
}

///|
test "Sorted Set preserves narrow parsers and rejects encoded cardinality" {
  let body = b"\x05\x00\x01\x00\x00\x00\x00\x00\x00\x00\xf0\x3f"
  assert_true(
    strings_error(empty_file(body))
    is UnsupportedObjectType(object_type=b'\x05', ..),
  )
  assert_true(
    empty_error(empty_file(body))
    is UnsupportedObjectType(object_type=b'\x05', ..),
  )
  assert_true(
    zset_error(empty_file(b"\x05\x00\xc0")) is UnexpectedEncodedLength(..),
  )
  for code in [3, 12, 21] {
    assert_true(
      zset_error(empty_file(([code.to_byte()] : Bytes)))
      is UnsupportedObjectType(..),
    )
  }
}

///|
test "compressed packed score error retains container and inner offsets" {
  let blob = b"\x0c\x00\x00\x00\x02\x00\x81a\x02\x01\x02\xff"
  let body = b"\x11\x00\xc3\x0d\x0c\x0b" + blob
  assert_true(
    zset_error(empty_file(body))
    is InvalidListpack(offset=11, inner_offset=10, ..),
  )
}
