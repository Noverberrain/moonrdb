// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
// Synthetic files use disabled checksums unless a real fixture is read below.
fn empty_file(body : Bytes) -> Bytes {
  b"REDIS0011" + body + b"\xff\x00\x00\x00\x00\x00\x00\x00\x00"
}

///|
fn empty_error(
  input : Bytes,
  max_input_bytes~ : Int32 = 64 * 1024 * 1024,
  max_string_bytes~ : Int32 = 1024 * 1024,
  max_metadata_entries~ : Int32 = 4096,
) -> @moonrdb.ParseError raise {
  try
    @moonrdb.parse_empty(
      input,
      max_input_bytes~,
      max_string_bytes~,
      max_metadata_entries~,
    )
  catch {
    error => error
  } noraise {
    _ => fail("expected complete-file parse failure")
  }
}

///|
test "minimal synthetic empty file reports disabled checksum" {
  let result = @moonrdb.parse_empty(
    empty_file(b""),
    max_metadata_entries=0,
    max_string_bytes=0,
  )
  assert_eq(result.format_version, 11)
  assert_eq(result.file_size, 18)
  assert_eq(result.aux_fields.length(), 0)
  assert_eq(result.database_selections.length(), 0)
  assert_eq(result.resize_hints.length(), 0)
  assert_true(result.checksum is Disabled)
}

///|
async test "real empty snapshot parses AUX and validates Redis CRC64" {
  let input = @fs.read_binary("fixtures/redis-7.2.5/empty.rdb")
  let result = @moonrdb.parse_empty(input)
  assert_eq(result.file_size, 88)
  assert_eq(result.aux_fields.length(), 5)
  assert_eq(result.aux_fields[0].key, b"redis-ver")
  assert_eq(result.aux_fields[0].value, b"7.2.5")
  assert_eq(result.aux_fields[1].value, b"64")
  assert_eq(result.aux_fields[2].value, b"1793453815")
  assert_eq(result.aux_fields[3].value, b"673893")
  assert_eq(result.aux_fields[4].value, b"0")
  assert_true(result.checksum is Valid(_))
}

///|
async test "real checksum-disabled snapshot is never reported as validated" {
  let input = @fs.read_binary("fixtures/redis-7.2.5-no-checksum/empty.rdb")
  let result = @moonrdb.parse_empty(input)
  assert_eq(result.file_size, 88)
  assert_eq(result.aux_fields[0].value, b"7.2.5")
  assert_true(result.checksum is Disabled)
}

///|
async test "every truncated real file prefix fails without a success result" {
  let input = @fs.read_binary("fixtures/redis-7.2.5/empty.rdb")
  for size in 0..<input.length() {
    assert_true(empty_error(input[:size].to_owned()) is UnexpectedEnd(..))
  }
}

///|
async test "single-bit corruption at every real snapshot byte is rejected" {
  let input = @fs.read_binary("fixtures/redis-7.2.5/empty.rdb")
  for offset in 0..<input.length() {
    let bad = Bytes::makei(input.length(), i => {
      if i == offset {
        (input[i].to_int() ^ 1).to_byte()
      } else {
        input[i]
      }
    })
    ignore(empty_error(bad))
  }
}

///|
async test "validly structured data and checksum mutations fail CRC at the trailer" {
  let input = @fs.read_binary("fixtures/redis-7.2.5/empty.rdb")
  for offset in [25, 87] {
    let bad = Bytes::makei(input.length(), i => {
      if i == offset {
        (input[i].to_int() ^ 1).to_byte()
      } else {
        input[i]
      }
    })
    assert_true(empty_error(bad) is ChecksumMismatch(offset=80, ..))
  }
}

///|
test "trailing bytes are rejected even when the checksum is disabled" {
  assert_true(
    empty_error(empty_file(b"") + b"extra")
    is TrailingData(offset=18, remaining=5),
  )
  assert_true(
    empty_error(b"REDIS0011")
    is UnexpectedEnd(offset=9, needed=1UL, remaining=0),
  )
  for size in 0..<8 {
    let input = b"REDIS0011\xff" +
      b"\x00\x00\x00\x00\x00\x00\x00\x00"[:size].to_owned()
    let error = empty_error(input)
    guard error is UnexpectedEnd(offset=10, needed=8UL, remaining~) else {
      fail("expected short checksum")
    }
    assert_eq(remaining, size)
  }
}

///|
test "binary AUX and duplicate keys preserve input bytes and order" {
  let body = b"\xfa\x03\x00\xffk\x02\x00\x80\xfa\x03\x00\xffk\x01x"
  let result = @moonrdb.parse_empty(empty_file(body))
  assert_eq(result.aux_fields.length(), 2)
  assert_eq(result.aux_fields[0].key, b"\x00\xffk")
  assert_eq(result.aux_fields[0].value, b"\x00\x80")
  assert_eq(result.aux_fields[1].key, b"\x00\xffk")
  assert_eq(result.aux_fields[1].value, b"x")
}

///|
test "AUX integer strings normalize signed decimal bytes including integer keys" {
  let body = b"\xfa\x01a\xc0\xff\xfa\x01b\xc1\x00\x80\xfa\x01c\xc2\x00\x00\x00\x80\xfa\xc0\xff\xc0\x80"
  let result = @moonrdb.parse_empty(empty_file(body))
  assert_eq(result.aux_fields[0].value, b"-1")
  assert_eq(result.aux_fields[1].value, b"-32768")
  assert_eq(result.aux_fields[2].value, b"-2147483648")
  assert_eq(result.aux_fields[3].key, b"-1")
  assert_eq(result.aux_fields[3].value, b"-128")
}

///|
test "database selections and resize hints retain scope without allocating tables" {
  let body = b"\xfb\x00\x00\xfe\x01\xfb\x03\x02\xfe\x00\xfb\x81\xff\xff\xff\xff\xff\xff\xff\xff\x00\xfe\x01"
  let result = @moonrdb.parse_empty(empty_file(body))
  assert_eq(result.database_selections, [1UL, 0UL, 1UL])
  assert_eq(result.resize_hints.length(), 3)
  assert_eq(result.resize_hints[0].database, 0UL)
  assert_eq(result.resize_hints[1].database, 1UL)
  assert_eq(result.resize_hints[1].keys, 3UL)
  assert_eq(result.resize_hints[1].expires, 2UL)
  assert_eq(result.resize_hints[2].database, 0UL)
  assert_eq(result.resize_hints[2].keys, 0xffffffffffffffffUL)
}

///|
test "all known object encodings and unsupported globals fail at their opcode" {
  for value in 0..<245 {
    let error = empty_error(empty_file(([value.to_byte()] : Bytes)))
    if value <= 7 || (value >= 9 && value <= 21) {
      guard error is UnsupportedObjectType(offset=9, object_type~) else {
        fail("expected unsupported object")
      }
      assert_eq(object_type, value.to_byte())
    } else {
      guard error is UnsupportedOpcode(offset=9, opcode~) else {
        fail("expected unsupported opcode")
      }
      assert_eq(opcode, value.to_byte())
    }
  }
  for value in [245, 246, 247] {
    assert_true(
      empty_error(empty_file(([value.to_byte()] : Bytes)))
      is UnsupportedOpcode(offset=9, ..),
    )
  }
}

///|
test "encoded counts and AUX LZF are rejected without guessing payload lengths" {
  assert_true(
    empty_error(empty_file(b"\xfe\xc0")) is UnexpectedEncodedLength(offset=10),
  )
  assert_true(
    empty_error(empty_file(b"\xfb\x00\xc3"))
    is UnexpectedEncodedLength(offset=11),
  )
  assert_true(
    empty_error(empty_file(b"\xfa\xc3"))
    is UnsupportedStringEncoding(offset=10, encoding=3),
  )
  assert_true(
    empty_error(empty_file(b"\xfa\x00\xc4"))
    is InvalidStringEncoding(offset=11, encoding=4),
  )
}

///|
test "resource limits reject negative configuration and oversized strings" {
  assert_true(
    empty_error(empty_file(b""), max_input_bytes=17) is InputTooLarge(..),
  )
  assert_true(
    empty_error(empty_file(b""), max_string_bytes=-1)
    is InvalidResourceLimit(offset=0, resource="aux-string-bytes", limit=-1),
  )
  assert_true(
    empty_error(empty_file(b""), max_metadata_entries=-1)
    is InvalidResourceLimit(offset=0, resource="metadata-entries", limit=-1),
  )
  let input = empty_file(b"\xfa\x03key\x03val")
  assert_eq(
    @moonrdb.parse_empty(input, max_string_bytes=3).aux_fields.length(),
    1,
  )
  assert_true(
    empty_error(input, max_string_bytes=2)
    is ResourceLimitExceeded(
      offset=10,
      resource="aux-string-bytes",
      limit=2UL,
      actual=3UL
    ),
  )
  assert_true(
    empty_error(empty_file(b"\xfa\x00\xc0\xff"), max_string_bytes=1)
    is ResourceLimitExceeded(offset=11, actual=2UL, ..),
  )
  let huge = empty_file(b"\xfa\x81\xff\xff\xff\xff\xff\xff\xff\xff")
  assert_true(
    empty_error(huge)
    is ResourceLimitExceeded(offset=10, actual=0xffffffffffffffffUL, ..),
  )
}

///|
test "global metadata count limit applies across AUX SELECTDB and RESIZEDB" {
  let input = empty_file(b"\xfe\x01\xfb\x00\x00\xfa\x00\x00")
  assert_eq(
    @moonrdb.parse_empty(input, max_metadata_entries=3).aux_fields.length(),
    1,
  )
  assert_true(
    empty_error(input, max_metadata_entries=2)
    is ResourceLimitExceeded(
      offset=14,
      resource="metadata-entries",
      limit=2UL,
      actual=3UL
    ),
  )
  assert_true(
    empty_error(input, max_metadata_entries=0)
    is ResourceLimitExceeded(offset=9, ..),
  )
}

///|
test "key metadata never becomes a successful empty snapshot" {
  assert_true(
    empty_error(empty_file(b"\xfc\x01\x00\x00\x00\x00\x00\x00\x00"))
    is DanglingKeyMetadata(offset=9),
  )
  assert_true(
    empty_error(empty_file(b"\xf8\x00\xfe\x00"))
    is DanglingKeyMetadata(offset=9),
  )
  assert_true(
    empty_error(empty_file(b"\xf9\xff\x00"))
    is UnsupportedObjectType(offset=11, object_type=b'\x00'),
  )
  assert_true(
    empty_error(b"REDIS0011\xfc\x00")
    is UnexpectedEnd(offset=10, needed=8UL, remaining=1),
  )
}
