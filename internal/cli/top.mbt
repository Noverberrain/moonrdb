// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn top_meta(
  record : @moonrdb.RdbRecord,
) -> (UInt64, Bytes, UInt64, Int32, String, String, Int32, String) {
  match record {
    String(r) =>
      (
        r.database,
        r.key,
        r.serialized_bytes,
        r.record_start,
        "String",
        repr(r.value_storage),
        r.value.length(),
        "value_bytes",
      )
    Hash(r) =>
      (
        r.database,
        r.key,
        r.serialized_bytes,
        r.record_start,
        "Hash",
        repr(r.storage),
        r.entries.length(),
        "entries",
      )
    List(r) =>
      (
        r.database,
        r.key,
        r.serialized_bytes,
        r.record_start,
        "List",
        "Quicklist2",
        r.items.length(),
        "items",
      )
    Set(r) =>
      (
        r.database,
        r.key,
        r.serialized_bytes,
        r.record_start,
        "Set",
        repr(r.storage),
        r.members.length(),
        "members",
      )
    SortedSet(r) =>
      (
        r.database,
        r.key,
        r.serialized_bytes,
        r.record_start,
        "SortedSet",
        repr(r.storage),
        r.entries.length(),
        "members",
      )
  }
}

///|
// Max heap of ranking tuples: the worst retained candidate is at index zero.
// Negative size sorts biggest first; remaining keys define a total stable order.
fn top_indices(
  records : Array[@moonrdb.RdbRecord],
  limit : Int32,
) -> Array[Int32] {
  let heap : Array[TopRank] = []
  if limit <= 0 {
    return []
  }
  for index in 0..<records.length() {
    let (db, key, size, start, _, _, _, _) = top_meta(records[index])
    let candidate = TopRank::{
      size: -size.reinterpret_as_int64(),
      db,
      key,
      start,
      index,
    }
    if heap.length() < limit {
      heap.push(candidate)
      let mut child = heap.length() - 1
      while child > 0 {
        let parent = (child - 1) / 2
        if heap[parent].compare(heap[child]) >= 0 {
          break
        }
        let tmp = heap[parent]
        heap[parent] = heap[child]
        heap[child] = tmp
        child = parent
      }
    } else if candidate.compare(heap[0]) < 0 {
      heap[0] = candidate
      let mut parent = 0
      while parent * 2 + 1 < heap.length() {
        let left = parent * 2 + 1
        let right = left + 1
        let child = if right < heap.length() &&
          heap[right].compare(heap[left]) > 0 {
          right
        } else {
          left
        }
        if heap[parent].compare(heap[child]) >= 0 {
          break
        }
        let tmp = heap[parent]
        heap[parent] = heap[child]
        heap[child] = tmp
        parent = child
      }
    }
  }
  heap.sort()
  heap.map(rank => rank.index)
}

///|
pub fn top_report(snapshot : @moonrdb.Snapshot, limit : Int32) -> String {
  let selected = top_indices(snapshot.records, limit)
  let out = StringBuilder()
  out.write_string(
    "MoonRDB top\nby: serialized-bytes\nlimit: \{limit}\nkeys: \{snapshot.records.length()}\nreturned: \{selected.length()}\n",
  )
  for rank in 0..<selected.length() {
    let (db, key, size, start, kind, storage, count, unit) = top_meta(
      snapshot.records[selected[rank]],
    )
    out.write_string(
      "rank=\{rank+1} db=\{db} key_base64=\{@base64.encode(key[:])} serialized_bytes=\{size} type=\{kind} encoding=\{storage} \{unit}=\{count} record_start=\{start}\n",
    )
  }
  out.write_string("size_basis: serialized RDB bytes (not Redis RAM)\n")
  match snapshot.checksum {
    Valid(_) => out.write_string("checksum: valid (CRC64)\n")
    Disabled => out.write_string("checksum: disabled (CRC64 not validated)\n")
  }
  out.write_string("status: complete\n")
  out.to_string()
}

///|
priv struct TopRank {
  size : Int64
  db : UInt64
  key : Bytes
  start : Int32
  index : Int32
} derive(Eq)

///|
impl Compare for TopRank with fn compare(a, b) {
  if a.size != b.size {
    return a.size.compare(b.size)
  }
  if a.db != b.db {
    return a.db.compare(b.db)
  }
  for i in 0..<Int32::min(a.key.length(), b.key.length()) {
    if a.key[i] != b.key[i] {
      return a.key[i].to_int().compare(b.key[i].to_int())
    }
  }
  if a.key.length() != b.key.length() {
    return a.key.length().compare(b.key.length())
  }
  if a.start != b.start {
    return a.start.compare(b.start)
  }
  a.index.compare(b.index)
}

///|
extend TopRank with Compare::{compare}
