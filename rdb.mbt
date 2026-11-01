// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
/// Parse a complete, object-free format-11 snapshot, including CRC64.
/// AUX LZF strings, objects, functions and modules are not supported yet.
/// Arrays preserve file order; RESIZEDB numbers are only hints.
///
/// ```mbt check
/// test {
///   let result = @moonrdb.parse_empty(
///     b"REDIS0011\xff\x00\x00\x00\x00\x00\x00\x00\x00",
///   )
///   assert_true(result.checksum is Disabled)
/// }
/// ```
pub fn parse_empty(
  input : Bytes,
  max_input_bytes~ : Int32 = 64 * 1024 * 1024,
  max_string_bytes~ : Int32 = 1024 * 1024,
  max_metadata_entries~ : Int32 = 4096,
) -> EmptySnapshot raise ParseError {
  let result = parse_snapshot(
    input,
    max_input_bytes,
    max_string_bytes,
    max_metadata_entries,
    0,
    2147483647,
    allow_strings=false,
  )
  {
    format_version: result.format_version,
    aux_fields: result.aux_fields,
    database_selections: result.database_selections,
    resize_hints: result.resize_hints,
    checksum: result.checksum,
    file_size: result.file_size,
  }
}

///|
/// Parse a complete format-11 snapshot containing only String objects.
/// Retains all decoded records and absolute expiration times, including expired
/// keys. The decoded-byte budget counts AUX, keys and values before allocation.
///
/// ```mbt check
/// test {
///   let result = @moonrdb.parse_strings(
///     b"REDIS0011\x00\x01k\x01v\xff\x00\x00\x00\x00\x00\x00\x00\x00",
///   )
///   assert_eq(result.records[0].value, b"v")
/// }
/// ```
pub fn parse_strings(
  input : Bytes,
  max_input_bytes~ : Int32 = 64 * 1024 * 1024,
  max_string_bytes~ : Int32 = 1024 * 1024,
  max_metadata_entries~ : Int32 = 4096,
  max_records~ : Int32 = 100000,
  max_decoded_bytes~ : Int32 = 64 * 1024 * 1024,
) -> StringSnapshot raise ParseError {
  let result = parse_snapshot(
    input,
    max_input_bytes,
    max_string_bytes,
    max_metadata_entries,
    max_records,
    max_decoded_bytes,
    allow_strings=true,
  )
  let records = result.records.map(record => {
    match record {
      String(value) => value
      Hash(value) =>
        raise UnsupportedObjectType(
          offset=value.record_start,
          object_type=b'\x04',
        )
    }
  })
  {
    format_version: result.format_version,
    aux_fields: result.aux_fields,
    database_selections: result.database_selections,
    resize_hints: result.resize_hints,
    records,
    checksum: result.checksum,
    file_size: result.file_size,
    global_overhead_bytes: result.global_overhead_bytes,
  }
}

///|
fn parse_snapshot(
  input : Bytes,
  max_input_bytes : Int32,
  max_string_bytes : Int32,
  max_metadata_entries : Int32,
  max_records : Int32,
  max_decoded_bytes : Int32,
  allow_strings~ : Bool,
  allow_hashes~ : Bool = false,
  max_hash_entries~ : Int32 = 100000,
  max_packed_bytes~ : Int32 = 4 * 1024 * 1024,
) -> Snapshot raise ParseError {
  let reader = Reader::new(input, max_input_bytes~)
  for
    (resource, limit) in [
      (
        if allow_strings {
          "string-bytes"
        } else {
          "aux-string-bytes"
        },
        max_string_bytes,
      ),
      ("metadata-entries", max_metadata_entries),
      ("records", max_records),
      ("decoded-bytes", max_decoded_bytes),
      ("hash-entries", max_hash_entries),
      ("packed-bytes", max_packed_bytes),
    ] {
    if limit < 0 {
      raise InvalidResourceLimit(offset=0, resource~, limit~)
    }
  }
  let format_version = reader.read_header()
  let aux_fields = []
  let database_selections = []
  let resize_hints = []
  let records = []
  let budget : DecodeBudget = { limit: max_decoded_bytes, used: 0, }
  let mut record_bytes = 0UL
  let mut database = 0UL
  let mut entries = 0
  for ;; {
    let offset = reader.pos
    let opcode = reader.read_u8()
    match opcode.to_int() {
      255 => {
        let checksum_offset = reader.pos
        let stored = reader.read_u64_le()
        if reader.remaining() != 0 {
          raise TrailingData(offset=reader.pos, remaining=reader.remaining())
        }
        let checksum = if stored == 0UL {
          Disabled
        } else {
          let computed = crc64(input[:checksum_offset])
          if stored != computed {
            raise ChecksumMismatch(offset=checksum_offset, stored~, computed~)
          }
          Valid(stored)
        }
        return {
          format_version,
          aux_fields,
          database_selections,
          resize_hints,
          records,
          checksum,
          file_size: input.length(),
          global_overhead_bytes: input.length().to_uint64() - record_bytes,
        }
      }
      250 | 254 | 251 => {
        // Limit before allocating or appending to any retained metadata array.
        check_resource_limit(
          "metadata-entries",
          offset,
          entries.to_uint64() + 1UL,
          max_metadata_entries,
        )
        entries += 1
        match opcode.to_int() {
          250 => {
            let key = reader.read_aux_string(
              max_string_bytes,
              budget,
              allow_lzf=allow_strings,
            )
            let value = reader.read_aux_string(
              max_string_bytes,
              budget,
              allow_lzf=allow_strings,
            )
            aux_fields.push({ key, value, })
          }
          254 => {
            database = reader.read_count()
            database_selections.push(database)
          }
          _ => {
            let keys = reader.read_count()
            let expires = reader.read_count()
            resize_hints.push({ database, keys, expires, })
          }
        }
      }
      248 | 249 | 252 | 253 => {
        let prefix = reader.read_key_prefix(opcode, offset)
        if !supported_type(prefix.object_type, allow_strings, allow_hashes) {
          raise UnsupportedObjectType(
            offset=prefix.type_offset,
            object_type=prefix.object_type,
          )
        }
        check_resource_limit(
          "records",
          prefix.start,
          records.length().to_uint64() + 1UL,
          max_records,
        )
        let record = reader.read_record(
          prefix, database, max_string_bytes, max_hash_entries, max_packed_bytes,
          budget,
        )
        record_bytes += record_size(record)
        records.push(record)
      }
      _ =>
        if is_object_type(opcode) {
          if !supported_type(opcode, allow_strings, allow_hashes) {
            raise UnsupportedObjectType(offset~, object_type=opcode)
          }
          check_resource_limit(
            "records",
            offset,
            records.length().to_uint64() + 1UL,
            max_records,
          )
          let prefix : KeyPrefix = {
            start: offset,
            type_offset: offset,
            object_type: opcode,
            expires_at_ms: None,
            idle_seconds: None,
            frequency: None,
          }
          let record = reader.read_record(
            prefix, database, max_string_bytes, max_hash_entries, max_packed_bytes,
            budget,
          )
          record_bytes += record_size(record)
          records.push(record)
        } else {
          raise UnsupportedOpcode(offset~, opcode~)
        }
    }
  }
}

///|
/// Parse a complete version-11 snapshot of the supported String and Hash types.
/// Packed container scratch space is bounded separately from returned data.
///
/// ```mbt check
/// test {
///   let result = @moonrdb.parse(
///     b"REDIS0011\x04\x01k\x01\x01f\x01v\xff\x00\x00\x00\x00\x00\x00\x00\x00",
///   )
///   assert_eq(result.records.length(), 1)
/// }
/// ```
pub fn parse(
  input : Bytes,
  max_input_bytes~ : Int32 = 64 * 1024 * 1024,
  max_string_bytes~ : Int32 = 1024 * 1024,
  max_metadata_entries~ : Int32 = 4096,
  max_records~ : Int32 = 100000,
  max_decoded_bytes~ : Int32 = 64 * 1024 * 1024,
  max_hash_entries~ : Int32 = 100000,
  max_packed_bytes~ : Int32 = 4 * 1024 * 1024,
) -> Snapshot raise ParseError {
  parse_snapshot(
    input,
    max_input_bytes,
    max_string_bytes,
    max_metadata_entries,
    max_records,
    max_decoded_bytes,
    allow_strings=true,
    allow_hashes=true,
    max_hash_entries~,
    max_packed_bytes~,
  )
}

///|
fn supported_type(value : Byte, strings : Bool, hashes : Bool) -> Bool {
  (strings && value == b'\x00') ||
  (hashes && (value == b'\x04' || value == b'\x10'))
}

///|
fn record_size(record : RdbRecord) -> UInt64 {
  match record {
    String(value) => value.serialized_bytes
    Hash(value) => value.serialized_bytes
  }
}

///|
fn Reader::read_record(
  self : Reader,
  prefix : KeyPrefix,
  database : UInt64,
  max_string_bytes : Int32,
  max_hash_entries : Int32,
  max_packed_bytes : Int32,
  budget : DecodeBudget,
) -> RdbRecord raise ParseError {
  if prefix.object_type == b'\x00' {
    String(self.read_string_record(prefix, database, max_string_bytes, budget))
  } else {
    Hash(
      self.read_hash_record(
        prefix, database, max_string_bytes, max_hash_entries, max_packed_bytes, budget,
      ),
    )
  }
}
