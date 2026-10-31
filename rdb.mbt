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
  let reader = Reader::new(input, max_input_bytes~)
  for
    (resource, limit) in [
      ("aux-string-bytes", max_string_bytes),
      ("metadata-entries", max_metadata_entries),
    ] {
    if limit < 0 {
      raise InvalidResourceLimit(offset=0, resource~, limit~)
    }
  }
  let format_version = reader.read_header()
  let aux_fields = []
  let database_selections = []
  let resize_hints = []
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
          checksum,
          file_size: input.length(),
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
            let key = reader.read_aux_string(max_string_bytes)
            let value = reader.read_aux_string(max_string_bytes)
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
        raise UnsupportedObjectType(
          offset=prefix.type_offset,
          object_type=prefix.object_type,
        )
      }
      _ => {
        if is_object_type(opcode) {
          raise UnsupportedObjectType(offset~, object_type=opcode)
        }
        raise UnsupportedOpcode(offset~, opcode~)
      }
    }
  }
}
