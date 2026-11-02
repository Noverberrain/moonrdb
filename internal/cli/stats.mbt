// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
pub fn stats_report(
  snapshot : @moonrdb.Snapshot,
  at_ms~ : Int64? = None,
  prefixes~ : Array[String] = [],
) -> String {
  let encoded = prefixes.map(p => @utf8.encode(p[:]))
  let prefix_counts = prefixes.map(_ => (0, 0UL, 0))
  let ttl = Array::make(7, 0)
  let groups : Map[(UInt64, String), (Int32, UInt64, Int32)] = Map([])
  let mut total = 0UL
  for record in snapshot.records {
    let (db, kind, size, expiry, key) = match record {
      String(r) =>
        (r.database, "String", r.serialized_bytes, r.expires_at_ms, r.key)
      Hash(r) =>
        (r.database, "Hash", r.serialized_bytes, r.expires_at_ms, r.key)
      List(r) =>
        (r.database, "List", r.serialized_bytes, r.expires_at_ms, r.key)
      Set(r) => (r.database, "Set", r.serialized_bytes, r.expires_at_ms, r.key)
      SortedSet(r) =>
        (r.database, "SortedSet", r.serialized_bytes, r.expires_at_ms, r.key)
    }
    let (count, bytes, expires) = groups.get((db, kind)).unwrap_or((0, 0UL, 0))
    groups[(db, kind)] = (
      count + 1,
      bytes + size,
      expires + (if expiry is Some(_) { 1 } else { 0 }),
    )
    for i in 0..<encoded.length() {
      if bytes_prefix(key, encoded[i]) {
        let (n, bytes, expires) = prefix_counts[i]
        prefix_counts[i] = (
          n + 1,
          bytes + size,
          expires + (if expiry is Some(_) { 1 } else { 0 }),
        )
      }
    }
    if at_ms is Some(at) {
      let bucket = ttl_bucket(expiry, at)
      ttl[bucket] += 1
    }
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
  for i in 0..<prefixes.length() {
    let (n, bytes, expires) = prefix_counts[i]
    out.write_string(
      "prefix \{repr(prefixes[i])}: keys=\{n} serialized_bytes=\{bytes} with_expiry=\{expires} permanent=\{n-expires}\n",
    )
  }
  if at_ms is Some(at) {
    out.write_string("at_ms: \{at}\n")
    let labels = [
      "permanent", "expired", "ttl_le_1h", "ttl_1h_to_24h", "ttl_24h_to_7d", "ttl_7d_to_30d",
      "ttl_gt_30d",
    ]
    for i in 0..<labels.length() {
      out.write_string("\{labels[i]}: \{ttl[i]}\n")
    }
  } else {
    out.write_string("expiry_evaluation: not_requested\n")
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

///|
fn bytes_prefix(key : Bytes, prefix : Bytes) -> Bool {
  if prefix.length() > key.length() {
    return false
  }
  for i in 0..<prefix.length() {
    if key[i] != prefix[i] {
      return false
    }
  }
  true
}

///|
fn ttl_bucket(expiry : Int64?, at : Int64) -> Int32 {
  guard expiry is Some(expires) else { return 0 }
  if expires <= at {
    return 1
  }
  // Unsigned subtraction after comparison handles the full Int64 range.
  let delta = expires.reinterpret_as_uint64() - at.reinterpret_as_uint64()
  if delta <= 3600000UL {
    2
  } else if delta <= 86400000UL {
    3
  } else if delta <= 604800000UL {
    4
  } else if delta <= 2592000000UL {
    5
  } else {
    6
  }
}
