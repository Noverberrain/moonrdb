// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn diff_index(
  snapshot : @moonrdb.Snapshot,
  db : UInt64?,
  prefix : Bytes?,
) -> Map[(UInt64, Bytes), @moonrdb.RdbRecord] raise {
  let entries : Map[(UInt64, Bytes), @moonrdb.RdbRecord] = Map([])
  for record in snapshot.records {
    if export_match(record, db, prefix) {
      let (database, key, _, _, _, _, _, _) = top_meta(record)
      let identity = (database, key)
      if entries.contains(identity) {
        fail("duplicate database/key in comparison scope")
      }
      entries[identity] = record
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
  jsonl : Bool,
  group_by_db : Bool,
  group_prefixes : Array[String],
) -> String raise {
  let encoded = prefix.map(p => @utf8.encode(p[:]))
  let old = diff_index(before, db, encoded)
  let new = diff_index(after, db, encoded)
  let changes : Array[
    (
      Int64,
      UInt64,
      String,
      String,
      String,
      Int64,
      Int64,
      Bool,
      Bool,
      String,
      String,
      Bytes,
    ),
  ] = []
  let mut added = 0
  let mut removed = 0
  let mut type_changed = 0
  let mut size_changed = 0
  let mut content_changed = 0
  let mut expiry_changed = 0
  for identity, current in new {
    let (database, key) = identity
    let (kind, size) = diff_kind_size(current)
    let previous = old.get(identity)
    let (old_kind, old_size) = previous.map(diff_kind_size).unwrap_or(("-", 0L))
    let mut content = false
    let mut expiry = false
    if previous is Some(record) {
      content = old_kind == kind && !same_content(record, current)
      expiry = record_expiry(record) != record_expiry(current)
      if content {
        content_changed += 1
      }
      if expiry {
        expiry_changed += 1
      }
    }
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
    if previous is None ||
      old_kind != kind ||
      old_size != size ||
      content ||
      expiry {
      changes.push(
        (
          old_size - size,
          database,
          @base64.encode(key[:]),
          old_kind,
          kind,
          old_size,
          size,
          content,
          expiry,
          diff_expiry(previous),
          diff_expiry(Some(current)),
          key,
        ),
      )
    }
  }
  for identity, previous in old {
    if !new.contains(identity) {
      let (database, key) = identity
      let (kind, size) = diff_kind_size(previous)
      removed += 1
      changes.push(
        (
          size,
          database,
          @base64.encode(key[:]),
          kind,
          "-",
          size,
          0L,
          false,
          false,
          diff_expiry(Some(previous)),
          "-",
          key,
        ),
      )
    }
  }
  changes.sort()
  let out = StringBuilder()
  let shown = Int32::min(limit, changes.length())
  let before_checksum = if before.checksum is Valid(_) {
    "valid"
  } else {
    "disabled"
  }
  let after_checksum = if after.checksum is Valid(_) {
    "valid"
  } else {
    "disabled"
  }
  if jsonl {
    append_diff_json(out, {
      "schema": "moonrdb.diff.v1",
      "kind": "summary",
      "added": Json(added),
      "removed": Json(removed),
      "type_changed": Json(type_changed),
      "size_changed": Json(size_changed),
      "content_changed": Json(content_changed),
      "expiry_changed": Json(expiry_changed),
      "returned": Json(shown),
      "total_changes": Json(changes.length()),
      "before_checksum": Json::string(before_checksum),
      "after_checksum": Json::string(after_checksum),
    })
  } else {
    out.write_string(
      "MoonRDB diff\nadded: \{added}\nremoved: \{removed}\ntype_changed: \{type_changed}\nsize_changed: \{size_changed}\ncontent_changed: \{content_changed}\nexpiry_changed: \{expiry_changed}\nreturned: \{shown}\n",
    )
  }
  let db_totals : Map[UInt64, DiffTotals] = Map([])
  let prefix_totals = group_prefixes.map(_ => DiffTotals::empty())
  let encoded_groups = group_prefixes.map(value => @utf8.encode(value[:]))
  if group_by_db || !group_prefixes.is_empty() {
    for change in changes {
      let (_, database, _, _, _, old_size, size, _, _, _, _, key) = change
      if group_by_db {
        let totals = db_totals
          .get(database)
          .unwrap_or_else(() => DiffTotals::empty())
        totals.add(old_size, size)
        db_totals[database] = totals
      }
      for i in 0..<encoded_groups.length() {
        if bytes_prefix(key, encoded_groups[i]) {
          prefix_totals[i].add(old_size, size)
        }
      }
    }
  }
  let databases = db_totals.keys().collect()
  databases.sort()
  for database in databases {
    diff_group_line(
      out,
      jsonl,
      "database",
      database.to_string(),
      db_totals[database],
    )
  }
  for i in 0..<group_prefixes.length() {
    diff_group_line(out, jsonl, "prefix", group_prefixes[i], prefix_totals[i])
  }
  for i in 0..<shown {
    let (
      negative_delta,
      database,
      key,
      old_kind,
      kind,
      old_size,
      size,
      content,
      expiry,
      before_expiry,
      after_expiry,
      _,
    ) = changes[i]
    if jsonl {
      append_diff_json(out, {
        "kind": "change",
        "database": Json::string(database.to_string()),
        "key_base64": Json::string(key),
        "before_type": diff_optional_text(old_kind),
        "after_type": diff_optional_text(kind),
        "before_bytes": Json::string(old_size.to_string()),
        "after_bytes": Json::string(size.to_string()),
        "delta_bytes": Json::string((-negative_delta).to_string()),
        "content_changed": Json::boolean(content),
        "expiry_changed": Json::boolean(expiry),
        "before_expiry_ms": diff_optional_text(before_expiry),
        "after_expiry_ms": diff_optional_text(after_expiry),
      })
    } else {
      out.write_string(
        "db=\{database} key_base64=\{key} before_type=\{old_kind} after_type=\{kind} before_bytes=\{old_size} after_bytes=\{size} delta_bytes=\{-negative_delta} content_changed=\{content} expiry_changed=\{expiry} before_expiry_ms=\{before_expiry} after_expiry_ms=\{after_expiry}\n",
      )
    }
  }
  if jsonl {
    append_diff_json(out, { "kind": "complete" })
  } else {
    out.write_string(
      "before_checksum: \{before_checksum}\nafter_checksum: \{after_checksum}\nstatus: complete\n",
    )
  }
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
  jsonl : Bool,
  group_by_db : Bool,
  group_prefixes : Array[String],
) -> String {
  let old = @moonrdb.parse(
    read_input(before, max_input_bytes),
    max_input_bytes~,
  )
  let new = @moonrdb.parse(read_input(after, max_input_bytes), max_input_bytes~)
  diff_report(old, new, db, prefix, limit, jsonl, group_by_db, group_prefixes)
}

///|
fn diff_kind_size(record : @moonrdb.RdbRecord) -> (String, Int64) {
  let (_, _, size, _, kind, _, _, _) = top_meta(record)
  (kind, size.reinterpret_as_int64())
}

///|
fn record_expiry(record : @moonrdb.RdbRecord) -> Int64? {
  match record {
    String(r) => r.expires_at_ms
    Hash(r) => r.expires_at_ms
    List(r) => r.expires_at_ms
    Set(r) => r.expires_at_ms
    Stream(r) => r.expires_at_ms
    SortedSet(r) => r.expires_at_ms
  }
}

///|
fn[K : Hash + Eq, V : Eq] same_pairs(
  before : Array[(K, V)],
  after : Array[(K, V)],
) -> Bool {
  if before.length() != after.length() {
    return false
  }
  let indexed = Map(before[:])
  after.iter().all(pair => indexed.get(pair.0) == Some(pair.1))
}

///|
fn same_content(
  before : @moonrdb.RdbRecord,
  after : @moonrdb.RdbRecord,
) -> Bool {
  match (before, after) {
    (Stream(a), Stream(b)) => a.entries == b.entries
    (String(a), String(b)) => a.value == b.value
    (List(a), List(b)) => a.items == b.items
    (Hash(a), Hash(b)) =>
      same_pairs(
        a.entries.map(e => (e.field, e.value)),
        b.entries.map(e => (e.field, e.value)),
      )
    (Set(a), Set(b)) =>
      same_pairs(a.members.map(e => (e, ())), b.members.map(e => (e, ())))
    (SortedSet(a), SortedSet(b)) =>
      same_pairs(
        a.entries.map(e => (e.element, e.score)),
        b.entries.map(e => (e.element, e.score)),
      )
    _ => false
  }
}

///|
fn diff_expiry(record : @moonrdb.RdbRecord?) -> String {
  match record {
    None => "-"
    Some(value) =>
      match record_expiry(value) {
        None => "persistent"
        Some(ms) => ms.to_string()
      }
  }
}

///|
priv struct DiffTotals {
  mut count : Int32
  mut before : Int64
  mut after : Int64
}

///|
fn DiffTotals::empty() -> DiffTotals {
  { count: 0, before: 0L, after: 0L, }
}

///|
fn DiffTotals::add(self : DiffTotals, before : Int64, after : Int64) -> Unit {
  self.count += 1
  self.before += before
  self.after += after
}

///|
fn append_diff_json(out : StringBuilder, object : Json) -> Unit {
  out.write_string(object.stringify())
  out.write_string("\n")
}

///|
fn diff_optional_text(value : String) -> Json {
  if value == "-" {
    Json::null()
  } else {
    Json::string(value)
  }
}

///|
fn diff_group_line(
  out : StringBuilder,
  jsonl : Bool,
  field : String,
  value : String,
  totals : DiffTotals,
) -> Unit {
  let delta = totals.after - totals.before
  if jsonl {
    append_diff_json(out, {
      "kind": "group",
      "group_by": Json::string(field),
      "group": Json::string(value),
      "changes": Json(totals.count),
      "before_bytes": Json::string(totals.before.to_string()),
      "after_bytes": Json::string(totals.after.to_string()),
      "delta_bytes": Json::string(delta.to_string()),
    })
  } else {
    out.write_string(
      "group_by=\{field} group=\{Json::string(value).stringify()} changes=\{totals.count} before_bytes=\{totals.before} after_bytes=\{totals.after} delta_bytes=\{delta}\n",
    )
  }
}
