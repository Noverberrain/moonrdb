// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn diff_index(
  snapshot : @moonrdb.Snapshot,
  db : UInt64?,
  prefix : Bytes?,
) -> Map[(UInt64, Bytes), (String, Int64)] raise {
  let entries : Map[(UInt64, Bytes), (String, Int64)] = Map([])
  for record in snapshot.records {
    if export_match(record, db, prefix) {
      let (database, key, size, _, kind, _, _, _) = top_meta(record)
      let identity = (database, key)
      if entries.contains(identity) {
        fail("duplicate database/key in comparison scope")
      }
      entries[identity] = (kind, size.reinterpret_as_int64())
    }
  }
  entries
}

///|
fn diff_report(
  before : @moonrdb.Snapshot,
  after : @moonrdb.Snapshot,
  db : UInt64?,
  prefix : String?,
  limit : Int32,
) -> String raise {
  let encoded = prefix.map(p => @utf8.encode(p[:]))
  let old = diff_index(before, db, encoded)
  let new = diff_index(after, db, encoded)
  let changes : Array[(Int64, UInt64, String, String, String, Int64, Int64)] = []
  let mut added = 0
  let mut removed = 0
  let mut type_changed = 0
  let mut size_changed = 0
  for identity, current in new {
    let (database, key) = identity
    let (kind, size) = current
    let previous = old.get(identity)
    let (old_kind, old_size) = previous.unwrap_or(("-", 0L))
    if previous is None {
      added += 1
    } else {
      if old_kind != kind {
        type_changed += 1
      }
      if old_size != size {
        size_changed += 1
      }
    }
    if previous is None || old_kind != kind || old_size != size {
      changes.push(
        (
          old_size - size,
          database,
          @base64.encode(key[:]),
          old_kind,
          kind,
          old_size,
          size,
        ),
      )
    }
  }
  for identity, previous in old {
    if !new.contains(identity) {
      let (database, key) = identity
      let (kind, size) = previous
      removed += 1
      changes.push(
        (size, database, @base64.encode(key[:]), kind, "-", size, 0L),
      )
    }
  }
  changes.sort()
  let out = StringBuilder()
  let shown = Int32::min(limit, changes.length())
  out.write_string(
    "MoonRDB diff\nadded: \{added}\nremoved: \{removed}\ntype_changed: \{type_changed}\nsize_changed: \{size_changed}\nreturned: \{shown}\n",
  )
  for i in 0..<shown {
    let (negative_delta, database, key, old_kind, kind, old_size, size) = changes[i]
    out.write_string(
      "db=\{database} key_base64=\{key} before_type=\{old_kind} after_type=\{kind} before_bytes=\{old_size} after_bytes=\{size} delta_bytes=\{-negative_delta}\n",
    )
  }
  out.write_string(
    "before_checksum: \{if before.checksum is Valid(_) { "valid" } else { "disabled" }}\nafter_checksum: \{if after.checksum is Valid(_) { "valid" } else { "disabled" }}\nstatus: complete\n",
  )
  out.to_string()
}

///|
async fn diff_files(
  before : String,
  after : String,
  max_input_bytes : Int32,
  db : UInt64?,
  prefix : String?,
  limit : Int32,
) -> String {
  let old = @moonrdb.parse(
    read_input(before, max_input_bytes),
    max_input_bytes~,
  )
  let new = @moonrdb.parse(read_input(after, max_input_bytes), max_input_bytes~)
  diff_report(old, new, db, prefix, limit)
}
