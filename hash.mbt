// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn Reader::read_hash_record(
  self : Reader,
  prefix : KeyPrefix,
  database : UInt64,
  max_string_bytes : Int32,
  max_hash_entries : Int32,
  max_packed_bytes : Int32,
  budget : DecodeBudget,
) -> HashRecord raise ParseError {
  let key = self.read_string(
    max_string_bytes,
    budget,
    allow_lzf=true,
    resource="string-bytes",
  )
  let offset = self.pos
  let (entries, storage, packed_storage) : (
    Array[HashEntry],
    HashStorage,
    StringStorage?,
  ) = if prefix.object_type == b'\x04' {
    let count = self.read_count()
    check_resource_limit("hash-entries", offset, count, max_hash_entries)
    if count == 0UL {
      raise InvalidHash(offset~, reason="empty hash")
    }
    let entries = []
    let seen : Map[Bytes, Unit] = Map([])
    for _ in 0..<count.to_int() {
      let field_offset = self.pos
      let field = self.read_string(
          max_string_bytes,
          budget,
          allow_lzf=true,
          resource="string-bytes",
        ).value
      if seen.contains(field) {
        raise InvalidHash(offset=field_offset, reason="duplicate field")
      }
      seen[field] = ()
      let value = self.read_string(
          max_string_bytes,
          budget,
          allow_lzf=true,
          resource="string-bytes",
        ).value
      entries.push({ field, value, })
    }
    (entries, Hashtable, None)
  } else {
    let scratch : DecodeBudget = { limit: max_packed_bytes, used: 0, }
    let packed = self.read_string(
      max_packed_bytes,
      scratch,
      allow_lzf=true,
      resource="packed-bytes",
    )
    (
      decode_hash_listpack(
        packed.value,
        offset,
        max_string_bytes,
        max_hash_entries,
        budget,
      ),
      Listpack,
      Some(packed.storage),
    )
  }
  {
    database,
    key: key.value,
    key_storage: key.storage,
    entries,
    storage,
    packed_storage,
    expires_at_ms: prefix.expires_at_ms,
    idle_seconds: prefix.idle_seconds,
    frequency: prefix.frequency,
    record_start: prefix.start,
    record_end: self.pos,
    serialized_bytes: (self.pos - prefix.start).to_uint64(),
  }
}
