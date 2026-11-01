// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn strings_error(
  input : Bytes,
  max_string_bytes~ : Int32 = 1024 * 1024,
  max_records~ : Int32 = 100000,
  max_decoded_bytes~ : Int32 = 64 * 1024 * 1024,
) -> @moonrdb.ParseError raise {
  try
    @moonrdb.parse_strings(
      input,
      max_string_bytes~,
      max_records~,
      max_decoded_bytes~,
    )
  catch {
    error => error
  } noraise {
    _ => fail("expected String parse failure")
  }
}

///|
async test "String parser also accepts both existing real empty snapshots" {
  for name in ["redis-7.2.5", "redis-7.2.5-no-checksum"] {
    let result = @moonrdb.parse_strings(
      @fs.read_binary("fixtures/\{name}/empty.rdb"),
    )
    assert_eq(result.records.length(), 0)
    assert_eq(result.global_overhead_bytes, 88UL)
    if name == "redis-7.2.5" {
      assert_true(result.checksum is Valid(_))
    } else {
      assert_true(result.checksum is Disabled)
    }
  }
}

///|
test "binary keys empty strings and duplicate records preserve file semantics" {
  let result = @moonrdb.parse_strings(
    empty_file(b"\x00\x02\x00\xff\x02\x80\x00\x00\x00\x00\x00\x02\x00\xff\x01x"),
  )
  assert_eq(result.records.length(), 3)
  assert_eq(result.records[0].key, b"\x00\xff")
  assert_eq(result.records[0].value, b"\x80\x00")
  assert_eq(result.records[1].key, b"")
  assert_eq(result.records[1].value, b"")
  assert_eq(result.records[2].key, b"\x00\xff")
  assert_eq(result.records[2].value, b"x")
  assert_true(result.records[0].key_storage is Raw)
}

///|
test "integer encoded keys and values retain decimal bytes and actual storage" {
  let result = @moonrdb.parse_strings(
    empty_file(b"\x00\xc0\x80\xc1\x00\x80\x00\x01k\xc2\xff\xff\xff\x7f"),
  )
  assert_eq(result.records[0].key, b"-128")
  assert_eq(result.records[0].value, b"-32768")
  assert_true(result.records[0].key_storage is Integer8)
  assert_true(result.records[0].value_storage is Integer16)
  assert_eq(result.records[1].value, b"2147483647")
  assert_true(result.records[1].value_storage is Integer32)
}

///|
test "metadata and original compressed serialization are included in record ranges" {
  let body = b"\xfc\x00\x00\x00\x00\x00\x00\x00\x00\xf8\x00\xf9\xff\x00\x01k\xc3\x04\x06\x00a\x60\x00"
  let result = @moonrdb.parse_strings(empty_file(body))
  let record = result.records[0]
  assert_eq(record.expires_at_ms, Some(0L))
  assert_eq(record.idle_seconds, Some(0UL))
  assert_eq(record.frequency, Some(b'\xff'))
  assert_eq(record.value, b"aaaaaa")
  assert_true(record.value_storage is Lzf)
  assert_eq(record.record_start, 9)
  assert_eq(record.record_end, 9 + body.length())
  assert_eq(record.serialized_bytes, body.length().to_uint64())
  assert_eq(result.global_overhead_bytes, 18UL)
}

///|
test "new parser supports compressed AUX while old empty API keeps its boundary" {
  let input = empty_file(b"\xfa\x01k\xc3\x04\x06\x00a\x60\x00")
  assert_eq(@moonrdb.parse_strings(input).aux_fields[0].value, b"aaaaaa")
  assert_true(
    empty_error(input) is UnsupportedStringEncoding(offset=12, encoding=3),
  )
}

///|
async test "real Redis String snapshot matches all 15 persisted values and metadata" {
  let input = @fs.read_binary("fixtures/redis-7.2.5-strings/strings.rdb")
  let result = @moonrdb.parse_strings(input)
  let cases : Array[(UInt64, Bytes, Bytes)] = [
    (0UL, b"plain", b"hello world!"),
    (0UL, b"", b""),
    (0UL, b"\x00\xffkey", b"\x00\xff\x80value\x00"),
    (0UL, b"int8", b"-128"),
    (0UL, b"int16", b"-32768"),
    (0UL, b"int32", b"-2147483648"),
    (0UL, b"leading-zero", b"00123"),
    (0UL, b"wide-int", b"9007199254740993"),
    (0UL, b"lzf", b"abc".repeat(2048)),
    (0UL, b"key:" + b"K".repeat(1024), b"compressed-key-value"),
    (0UL, b"expiring", b"alive"),
    (2UL, b"plain", b"db two"),
    (2UL, b"int8-max", b"127"),
    (2UL, b"int16-max", b"32767"),
    (2UL, b"int32-max", b"2147483647"),
  ]
  assert_eq(result.records.length(), cases.length())
  assert_eq(result.database_selections, [0UL, 2UL])
  assert_true(result.checksum is Valid(_))
  for (database, key, value) in cases {
    let matches = result.records.filter(record => {
      record.database == database && record.key == key
    })
    assert_eq(matches.length(), 1)
    let record = matches[0]
    assert_eq(record.value, value)
    assert_true(record.idle_seconds is Some(_))
    assert_eq(record.frequency, None)
    if key == b"expiring" {
      assert_eq(record.expires_at_ms, Some(4102444800123L))
      assert_eq(input[record.record_start], b'\xfc')
    } else {
      assert_eq(record.expires_at_ms, None)
    }
    if key == b"int8" || key == b"int8-max" {
      assert_true(record.value_storage is Integer8)
    } else if key == b"int16" || key == b"int16-max" {
      assert_true(record.value_storage is Integer16)
    } else if key == b"int32" || key == b"int32-max" {
      assert_true(record.value_storage is Integer32)
    } else if key == b"lzf" {
      assert_true(record.value_storage is Lzf)
    } else {
      assert_true(record.value_storage is Raw)
    }
    if key.length() > 1000 {
      assert_true(record.key_storage is Lzf)
    }
  }
  let mut bytes = result.global_overhead_bytes
  let mut previous_end = 9
  for record in result.records {
    assert_true(record.record_start >= previous_end)
    assert_true(record.record_end > record.record_start)
    assert_eq(
      record.serialized_bytes,
      (record.record_end - record.record_start).to_uint64(),
    )
    bytes += record.serialized_bytes
    previous_end = record.record_end
  }
  assert_eq(bytes, input.length().to_uint64())
}

///|
async test "all real String file truncated prefixes and single-bit mutations fail" {
  let input = @fs.read_binary("fixtures/redis-7.2.5-strings/strings.rdb")
  for size in 0..<input.length() {
    ignore(strings_error(input[:size].to_owned()))
  }
  for offset in 0..<input.length() {
    let bad = Bytes::makei(input.length(), i => {
      if i == offset {
        (input[i].to_int() ^ 1).to_byte()
      } else {
        input[i]
      }
    })
    ignore(strings_error(bad))
  }
}

///|
test "record count and aggregate decoded-byte limits apply before unbounded work" {
  let input = empty_file(b"\xfa\x01a\x01b\x00\x01k\x04data")
  assert_eq(
    @moonrdb.parse_strings(input, max_decoded_bytes=7).records.length(),
    1,
  )
  assert_true(
    strings_error(input, max_decoded_bytes=6)
    is ResourceLimitExceeded(
      resource="decoded-bytes",
      actual=7UL,
      limit=6UL,
      ..
    ),
  )
  assert_true(
    strings_error(empty_file(b"\x00"), max_records=0)
    is ResourceLimitExceeded(offset=9, resource="records", ..),
  )
  assert_true(
    strings_error(input, max_records=-1)
    is InvalidResourceLimit(resource="records", ..),
  )
  assert_true(
    strings_error(input, max_decoded_bytes=-1)
    is InvalidResourceLimit(resource="decoded-bytes", ..),
  )
  assert_true(
    strings_error(input, max_string_bytes=3)
    is ResourceLimitExceeded(resource="string-bytes", actual=4UL, ..),
  )
}

///|
test "LZF declared size and aggregate budgets reject malicious expansion" {
  let huge = empty_file(b"\x00\x00\xc3\x01\x81\xff\xff\xff\xff\xff\xff\xff\xff")
  assert_true(
    strings_error(huge)
    is ResourceLimitExceeded(
      resource="string-bytes",
      actual=0xffffffffffffffffUL,
      ..
    ),
  )
  let valid = empty_file(b"\x00\x00\xc3\x04\x06\x00a\x60\x00")
  assert_eq(
    @moonrdb.parse_strings(valid, max_string_bytes=6, max_decoded_bytes=6).records[0].value,
    b"aaaaaa",
  )
  assert_true(
    strings_error(valid, max_string_bytes=5)
    is ResourceLimitExceeded(resource="string-bytes", actual=6UL, ..),
  )
  assert_true(
    strings_error(valid, max_decoded_bytes=5)
    is ResourceLimitExceeded(resource="decoded-bytes", actual=6UL, ..),
  )
}

///|
test "LZF length headers and malformed streams fail with explicit errors" {
  assert_true(
    strings_error(empty_file(b"\x00\x00\xc3\xc0"))
    is UnexpectedEncodedLength(..),
  )
  assert_true(
    strings_error(empty_file(b"\x00\x00\xc3\x00\xc3"))
    is UnexpectedEncodedLength(..),
  )
  assert_true(
    strings_error(empty_file(b"\x00\x00\xc3\x02\x03\x20\x00")) is InvalidLzf(..),
  )
  assert_true(
    strings_error(b"REDIS0011\x00\x00\xc3\x10\x03\x00") is UnexpectedEnd(..),
  )
  assert_true(
    strings_error(empty_file(b"\x00\xc4")) is InvalidStringEncoding(..),
  )
}

///|
test "non-String objects and unknown opcodes remain unsupported" {
  assert_true(
    strings_error(empty_file(b"\x04"))
    is UnsupportedObjectType(offset=9, object_type=b'\x04'),
  )
  assert_true(
    strings_error(empty_file(b"\xf9\x00\x14"))
    is UnsupportedObjectType(offset=11, object_type=b'\x14'),
  )
  assert_true(
    strings_error(empty_file(b"\xf5"))
    is UnsupportedOpcode(offset=9, opcode=b'\xf5'),
  )
}
