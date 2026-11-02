// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
pub fn stats_report(snapshot : @moonrdb.Snapshot) -> String {
  let groups : Map[(UInt64, String), (Int32, UInt64, Int32)] = Map([])
  let mut total = 0UL
  for record in snapshot.records {
    let (db, kind, size, expiry) = match record {
      String(r) => (r.database, "String", r.serialized_bytes, r.expires_at_ms)
      Hash(r) => (r.database, "Hash", r.serialized_bytes, r.expires_at_ms)
      List(r) => (r.database, "List", r.serialized_bytes, r.expires_at_ms)
      Set(r) => (r.database, "Set", r.serialized_bytes, r.expires_at_ms)
      SortedSet(r) =>
        (r.database, "SortedSet", r.serialized_bytes, r.expires_at_ms)
    }
    let (count, bytes, expires) = groups.get((db, kind)).unwrap_or((0, 0UL, 0))
    groups[(db, kind)] = (
      count + 1,
      bytes + size,
      expires + (if expiry is Some(_) { 1 } else { 0 }),
    )
    total += size
  }
  let keys = groups.keys().collect()
  keys.sort()
  let out = StringBuilder()
  out.write_string(
    "MoonRDB stats\nfile_bytes: \{snapshot.file_size}\nkeys: \{snapshot.records.length()}\n",
  )
  for (db, kind) in keys {
    let (count, bytes, expires) = groups[(db, kind)]
    out.write_string(
      "db \{db} type \{kind}: keys=\{count} serialized_bytes=\{bytes} with_expiry=\{expires} permanent=\{count - expires}\n",
    )
  }
  out.write_string(
    "record_bytes: \{total}\nglobal_overhead_bytes: \{snapshot.global_overhead_bytes}\n",
  )
  out.write_string(
    "accounting_matches: \{total + snapshot.global_overhead_bytes == snapshot.file_size.to_uint64()}\n",
  )
  out.write_string("size_basis: serialized RDB bytes (not Redis RAM)\n")
  match snapshot.checksum {
    Valid(_) => out.write_string("checksum: valid (CRC64)\n")
    Disabled => out.write_string("checksum: disabled (CRC64 not validated)\n")
  }
  out.write_string("status: complete\n")
  out.to_string()
}
