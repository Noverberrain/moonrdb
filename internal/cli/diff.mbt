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
        ),
      )
    }
  }
  changes.sort()
  let out = StringBuilder()
  let shown = Int32::min(limit, changes.length())
  out.write_string(
    "MoonRDB diff\nadded: \{added}\nremoved: \{removed}\ntype_changed: \{type_changed}\nsize_changed: \{size_changed}\ncontent_changed: \{content_changed}\nexpiry_changed: \{expiry_changed}\nreturned: \{shown}\n",
  )
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
    ) = changes[i]
    out.write_string(
      "db=\{database} key_base64=\{key} before_type=\{old_kind} after_type=\{kind} before_bytes=\{old_size} after_bytes=\{size} delta_bytes=\{-negative_delta} content_changed=\{content} expiry_changed=\{expiry} before_expiry_ms=\{before_expiry} after_expiry_ms=\{after_expiry}\n",
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
