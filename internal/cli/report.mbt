// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn record_database(record : @moonrdb.RdbRecord) -> UInt64 {
  match record {
    String(r) => r.database
    Hash(r) => r.database
    List(r) => r.database
    Set(r) => r.database
    SortedSet(r) => r.database
  }
}

///|
/// No raw AUX/key bytes or host paths are rendered to a terminal.
/// A selected empty database is listed; DB 0 is implicit for records before SELECTDB.
pub fn inspect_report(snapshot : @moonrdb.Snapshot) -> String {
  let counts : Map[UInt64, Int32] = Map([])
  for database in snapshot.database_selections {
    counts[database] = 0
  }
  for record in snapshot.records {
    let database = record_database(record)
    counts[database] = counts.get(database).unwrap_or(0) + 1
  }
  let databases = counts.keys().collect()
  databases.sort()
  let out = StringBuilder()
  out.write_string("MoonRDB inspect\n")
  out.write_string("format_version: \{snapshot.format_version}\n")
  out.write_string("file_bytes: \{snapshot.file_size}\n")
  out.write_string("keys: \{snapshot.records.length()}\n")
  out.write_string("aux_fields: \{snapshot.aux_fields.length()}\n")
  out.write_string("databases: \{databases.length()}\n")
  for database in databases {
    out.write_string("db \{database}: keys=\{counts[database]}\n")
  }
  match snapshot.checksum {
    Valid(_) => out.write_string("checksum: valid (CRC64)\n")
    Disabled => out.write_string("checksum: disabled (CRC64 not validated)\n")
  }
  out.write_string("status: complete\n")
  out.to_string()
}
