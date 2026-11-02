// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn list_error(
  input : Bytes,
  max_list_nodes~ : Int32 = 100000,
  max_list_items~ : Int32 = 100000,
  max_string_bytes~ : Int32 = 1024 * 1024,
  max_packed_bytes~ : Int32 = 4 * 1024 * 1024,
  max_decoded_bytes~ : Int32 = 64 * 1024 * 1024,
) -> @moonrdb.ParseError raise {
  try
    @moonrdb.parse(
      input,
      max_list_nodes~,
      max_list_items~,
      max_string_bytes~,
      max_packed_bytes~,
      max_decoded_bytes~,
    )
  catch {
    error => error
  } noraise {
    _ => fail("expected List parse failure")
  }
}

///|
fn only_list(input : Bytes) -> @moonrdb.ListRecord raise {
  let result = @moonrdb.parse(input)
  assert_eq(result.records.length(), 1)
  guard result.records[0] is List(record) else { fail("expected List record") }
  record
}

///|
test "mixed plain and packed nodes preserve odd item counts duplicates and empties" {
  let one = b"\x0a\x00\x00\x00\x01\x00\x81a\x02\xff"
  let three = b"\x0d\x00\x00\x00\x03\x00\x01\x01\x01\x01\x80\x01\xff"
  let body = b"\x12\x00\x03\x02\x0a" + one + b"\x01\x01b\x02\x0d" + three
  let record = only_list(empty_file(body))
  assert_eq(record.items, [b"a", b"b", b"1", b"1", b""])
  assert_eq(record.nodes.length(), 3)
  assert_true(record.nodes[0].container is Packed)
  assert_true(record.nodes[1].container is Plain)
  assert_true(record.nodes[2].container is Packed)
  assert_eq(record.nodes[0].item_start, 0)
  assert_eq(record.nodes[0].item_end, 1)
  assert_eq(record.nodes[1].item_start, 1)
  assert_eq(record.nodes[1].item_end, 2)
  assert_eq(record.nodes[2].item_start, 2)
  assert_eq(record.nodes[2].item_end, 5)
  assert_eq(record.serialized_bytes, body.length().to_uint64())
}

///|
test "plain nodes reuse binary integer and LZF string decoding" {
  let record = only_list(
    empty_file(
      b"\x12\x00\x03\x01\x02\x00\xff\x01\xc0\x7f\x01\xc3\x04\x06\x00a\x60\x00",
    ),
  )
  assert_eq(record.items, [b"\x00\xff", b"127", b"aaaaaa"])
  assert_true(record.nodes[0].storage is Raw)
  assert_true(record.nodes[1].storage is Integer8)
  assert_true(record.nodes[2].storage is Lzf)
}

///|
test "List retains absolute expiry and record range including key metadata" {
  let body = b"\xfc\x00\x00\x00\x00\x00\x00\x00\x00\xf9\xff\x12\x01k\x01\x01\x01v"
  let result = @moonrdb.parse(empty_file(body))
  guard result.records[0] is List(record) else { fail("expected List") }
  assert_eq(record.expires_at_ms, Some(0L))
  assert_eq(record.frequency, Some(b'\xff'))
  assert_eq(record.items, [b"v"])
  assert_eq(record.record_start, 9)
  assert_eq(record.record_end, 9 + body.length())
  assert_eq(record.serialized_bytes, body.length().to_uint64())
  assert_eq(result.global_overhead_bytes, 18UL)
}

///|
test "empty Lists and empty nodes fail with explicit errors" {
  assert_true(
    list_error(empty_file(b"\x12\x00\x00"))
    is InvalidList(reason="empty quicklist", ..),
  )
  assert_true(
    list_error(empty_file(b"\x12\x00\x01\x01\x00"))
    is InvalidList(reason="empty plain node", ..),
  )
  assert_true(
    list_error(empty_file(b"\x12\x00\x01\x02\x07\x07\x00\x00\x00\x00\x00\xff"))
    is InvalidList(reason="empty packed node", ..),
  )
}

///|
test "unknown containers encoded counts and legacy List representations fail closed" {
  for container in [0, 3, 63] {
    let body = b"\x12\x00\x01" + ([container.to_byte()] : Bytes)
    assert_true(
      list_error(empty_file(body))
      is InvalidList(offset=12, reason="unknown quicklist container"),
    )
  }
  assert_true(
    list_error(empty_file(b"\x12\x00\xc0"))
    is UnexpectedEncodedLength(offset=11),
  )
  assert_true(
    list_error(empty_file(b"\x12\x00\x01\xc0"))
    is UnexpectedEncodedLength(offset=12),
  )
  for code in [1, 10, 14] {
    assert_true(
      list_error(empty_file(([code.to_byte()] : Bytes)))
      is UnsupportedObjectType(..),
    )
  }
  let input = empty_file(b"\x12\x00\x01\x01\x01v")
  assert_true(
    strings_error(input) is UnsupportedObjectType(object_type=b'\x12', ..),
  )
  assert_true(
    empty_error(input) is UnsupportedObjectType(object_type=b'\x12', ..),
  )
}

///|
test "List node and item limits accumulate across the entire snapshot" {
  let input = empty_file(b"\x12\x00\x01\x01\x01x\x12\x00\x01\x01\x01y")
  assert_eq(
    @moonrdb.parse(input, max_list_nodes=2, max_list_items=2).records.length(),
    2,
  )
  assert_true(
    list_error(input, max_list_nodes=1)
    is ResourceLimitExceeded(resource="list-nodes", actual=2UL, limit=1UL, ..),
  )
  assert_true(
    list_error(input, max_list_items=1)
    is ResourceLimitExceeded(resource="list-items", actual=2UL, limit=1UL, ..),
  )
  let huge = empty_file(
    b"\x12\x00\x01\x01\x01x\x12\x00\x81\xff\xff\xff\xff\xff\xff\xff\xff",
  )
  assert_true(
    list_error(huge)
    is ResourceLimitExceeded(
      resource="list-nodes",
      actual=0xffffffffffffffffUL,
      ..
    ),
  )
  assert_true(
    list_error(input, max_list_nodes=-1)
    is InvalidResourceLimit(resource="list-nodes", ..),
  )
  assert_true(
    list_error(input, max_list_items=-1)
    is InvalidResourceLimit(resource="list-items", ..),
  )
}

///|
test "unknown listpack count and empty elements cannot bypass item limits" {
  let blob = b"\x0d\x00\x00\x00\xff\xff\x01\x01\x01\x01\x80\x01\xff"
  let input = empty_file(b"\x12\x00\x01\x02\x0d" + blob)
  assert_eq(@moonrdb.parse(input, max_list_items=3).records.length(), 1)
  assert_true(
    list_error(input, max_list_items=2)
    is ResourceLimitExceeded(resource="list-items", actual=3UL, ..),
  )
  assert_true(
    list_error(input, max_list_items=0)
    is ResourceLimitExceeded(resource="list-items", actual=1UL, ..),
  )
}

///|
test "packed node scratch is separate from decoded item and String limits" {
  let blob = b"\x0d\x00\x00\x00\x03\x00\x01\x01\x01\x01\x80\x01\xff"
  let input = empty_file(b"\x12\x00\x01\x02\x0d" + blob)
  assert_eq(
    @moonrdb.parse(
      input,
      max_string_bytes=1,
      max_packed_bytes=13,
      max_decoded_bytes=2,
    ).records.length(),
    1,
  )
  assert_true(
    list_error(input, max_packed_bytes=12)
    is ResourceLimitExceeded(resource="packed-bytes", actual=13UL, ..),
  )
  assert_true(
    list_error(input, max_decoded_bytes=1)
    is ResourceLimitExceeded(resource="decoded-bytes", actual=2UL, ..),
  )
  assert_eq(
    @moonrdb.parse(empty_file(b"\x12\x00\x01\x01\x01v"), max_packed_bytes=0).records.length(),
    1,
  )
}

///|
test "compressed packed nodes honor expansion caps and decoded error offsets" {
  let blob = b"\x0d\x00\x00\x00\x03\x00\x01\x01\x01\x01\x80\x01\xff"
  let input = empty_file(b"\x12\x00\x01\x02\xc3\x0e\x0d\x0c" + blob)
  let record = only_list(input)
  assert_eq(record.items, [b"1", b"1", b""])
  assert_true(record.nodes[0].storage is Lzf)
  assert_true(
    list_error(input, max_packed_bytes=12)
    is ResourceLimitExceeded(resource="packed-bytes", ..),
  )
  let bad = Bytes::makei(blob.length(), i => if i == 7 { 0 } else { blob[i] })
  assert_true(
    list_error(empty_file(b"\x12\x00\x01\x02\xc3\x0e\x0d\x0c" + bad))
    is InvalidListpack(offset=13, inner_offset=7, ..),
  )
  assert_true(
    list_error(
      empty_file(
        b"\x12\x00\x01\x02\xc3\x00\x81\xff\xff\xff\xff\xff\xff\xff\xff",
      ),
    )
    is ResourceLimitExceeded(
      resource="packed-bytes",
      actual=0xffffffffffffffffUL,
      ..
    ),
  )
}

///|
test "List listpack count mismatches and oversized declarations fail before success" {
  let mismatch = b"\x0d\x00\x00\x00\x02\x00\x01\x01\x01\x01\x80\x01\xff"
  assert_true(
    list_error(empty_file(b"\x12\x00\x01\x02\x0d" + mismatch))
    is InvalidListpack(offset=13, inner_offset=4, ..),
  )
  let oversized = b"\x07\x00\x00\x00\xfe\xff\xff"
  assert_true(
    list_error(
      empty_file(b"\x12\x00\x01\x02\x07" + oversized),
      max_list_items=2,
    )
    is ResourceLimitExceeded(resource="list-items", actual=65534UL, ..),
  )
  assert_true(
    list_error(b"REDIS0011\x12\x00\x02\x01\x01x") is UnexpectedEnd(..),
  )
}

///|
test "non-List records do not consume List node or item budgets" {
  let input = empty_file(b"\x00\x00\x01s\x04\x00\x01\x01f\x01v")
  assert_eq(
    @moonrdb.parse(input, max_list_nodes=0, max_list_items=0).records.length(),
    2,
  )
}

///|
test "all item kinds share the cumulative decoded-byte budget" {
  let input = empty_file(b"\x00\x00\x02zz\x12\x00\x01\x01\x01a")
  assert_eq(@moonrdb.parse(input, max_decoded_bytes=3).records.length(), 2)
  assert_true(
    list_error(input, max_decoded_bytes=2)
    is ResourceLimitExceeded(resource="decoded-bytes", actual=3UL, ..),
  )
  let compressed_plain = empty_file(
    b"\x12\x00\x01\x01\xc3\x04\x06\x00a\x60\x00",
  )
  assert_true(
    list_error(compressed_plain, max_string_bytes=5)
    is ResourceLimitExceeded(resource="string-bytes", actual=6UL, ..),
  )
}

///|
async test "real quicklist2 snapshot preserves ordered bytes and mixed node encodings" {
  let input = @fs.read_binary("fixtures/redis-7.2.5-lists/lists.rdb")
  let result = @moonrdb.parse(input)
  assert_eq(result.records.length(), 8)
  assert_true(result.checksum is Valid(_))
  assert_eq(result.database_selections, [0UL, 2UL])
  let compressed = [
    b"a".repeat(60),
    b"b".repeat(60),
    b"c".repeat(60),
    b"d".repeat(60),
  ]
  let values = Array::makei(20, i => compressed[i % 4])
  let cases : Array[(UInt64, Bytes, Array[Bytes])] = [
    (0UL, b"single", [b"\x00\xff", b""]),
    (
      0UL,
      b"ordered",
      [
        b"first", b"-128", b"first", b"\x80\x00", b"0", b"9223372036854775807", b"last",
      ],
    ),
    (0UL, b"compressed", values),
    (
      0UL,
      b"mixed",
      [
        b"head0",
        b"head1",
        b"\x00\xff" + b"p".repeat(126),
        b"tail0",
        b"tail1",
        b"tail2",
      ],
    ),
    (0UL, b"list:" + b"K".repeat(1024), [b"v0", b"v1", b"v2"]),
    (2UL, b"expiring", [b"a", b"b", b"c"]),
  ]
  for (db, key, expected) in cases {
    let matches = result.records.filter(record => {
      match record {
        List(value) => value.database == db && value.key == key
        _ => false
      }
    })
    assert_eq(matches.length(), 1)
    guard matches[0] is List(record) else { fail("expected List") }
    assert_eq(record.items, expected)
    assert_true(record.idle_seconds is Some(_))
    assert_eq(record.frequency, None)
    if key == b"expiring" {
      assert_eq(record.expires_at_ms, Some(4102444800123L))
    } else {
      assert_eq(record.expires_at_ms, None)
    }
    if key == b"single" {
      assert_eq(record.nodes.length(), 1)
    } else {
      assert_true(record.nodes.length() > 1)
    }
    if key == b"mixed" {
      assert_true(record.nodes.any(node => node.container is Plain))
      assert_true(record.nodes.any(node => node.container is Packed))
    }
    if key == b"compressed" {
      assert_true(record.nodes.any(node => node.storage is Lzf))
    }
    if key.length() > 1000 {
      assert_true(record.key_storage is Lzf)
    }
    let mut next_item = 0
    let mut previous_node_end = record.record_start
    for node in record.nodes {
      assert_eq(node.item_start, next_item)
      assert_true(node.item_end > node.item_start)
      assert_true(
        node.node_start >= previous_node_end && node.node_end > node.node_start,
      )
      assert_true(node.node_end <= record.record_end)
      assert_eq(
        input[node.node_start],
        if node.container is Plain {
          b'\x01'
        } else {
          b'\x02'
        },
      )
      if node.container is Plain {
        assert_eq(node.item_end - node.item_start, 1)
      }
      next_item = node.item_end
      previous_node_end = node.node_end
    }
    assert_eq(next_item, record.items.length())
    assert_eq(previous_node_end, record.record_end)
  }
  let mut total = result.global_overhead_bytes
  let mut previous_end = 9
  let mut markers = 0
  for record in result.records {
    let (start, end, size) = match record {
      SortedSet(_) => fail("unexpected Sorted Set")
      Set(_) => fail("unexpected Set in List fixture")
      List(value) =>
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
    }
    assert_true(start >= previous_end && end > start)
    assert_eq(size, (end - start).to_uint64())
    previous_end = end
    total += size
  }
  assert_eq(markers, 2)
  assert_eq(total, input.length().to_uint64())
}

///|
async test "every real List file short prefix and single-bit mutation is rejected" {
  let input = @fs.read_binary("fixtures/redis-7.2.5-lists/lists.rdb")
  for length in 0..<input.length() {
    ignore(list_error(input[:length].to_owned()))
  }
  for offset in 0..<input.length() {
    let bad = Bytes::makei(input.length(), i => {
      if i == offset {
        (input[i].to_int() ^ 1).to_byte()
      } else {
        input[i]
      }
    })
    ignore(list_error(bad))
  }
}
