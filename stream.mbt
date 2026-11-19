// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
pub(all) struct StreamRecord {
  database : UInt64
  key : Bytes
  key_storage : StringStorage
  entries : Array[StreamEntry]
  last_generated_id : StreamMessageId
  first_entry_id : StreamMessageId
  max_deleted_entry_id : StreamMessageId
  entries_added : UInt64
  length : UInt64
  group_count : UInt64
  groups : Array[StreamGroup]
  payload : Bytes
  expires_at_ms : Int64?
  idle_seconds : UInt64?
  frequency : Byte?
  record_start : Int32
  record_end : Int32
  serialized_bytes : UInt64
} derive(Debug, Eq)

///|
pub extend StreamRecord with @debug.Debug::{to_repr}

///|
pub extend StreamRecord with Eq::{equal, not_equal}

///|
pub(all) struct StreamMessageId {
  milliseconds : UInt64
  sequence : UInt64
} derive(Debug, Eq)

///|
pub extend StreamMessageId with @debug.Debug::{to_repr}

///|
pub extend StreamMessageId with Eq::{equal, not_equal}

///|
pub(all) struct StreamPending {
  id : StreamMessageId
  delivery_time_ms : Int64
  delivery_count : UInt64
} derive(Debug, Eq)

///|
pub extend StreamPending with @debug.Debug::{to_repr}

///|
pub extend StreamPending with Eq::{equal, not_equal}

///|
pub(all) struct StreamConsumer {
  name : Bytes
  seen_time_ms : Int64
  active_time_ms : Int64
  pending : Array[StreamPending]
} derive(Debug, Eq)

///|
pub extend StreamConsumer with @debug.Debug::{to_repr}

///|
pub extend StreamConsumer with Eq::{equal, not_equal}

///|
pub(all) struct StreamGroup {
  name : Bytes
  last_delivered_id : StreamMessageId
  entries_read : Int64
  consumers : Array[StreamConsumer]
  pending_count : UInt64
} derive(Debug, Eq)

///|
pub extend StreamGroup with @debug.Debug::{to_repr}

///|
pub extend StreamGroup with Eq::{equal, not_equal}

///|
fn Reader::stream_string(
  self : Reader,
  limit : Int32,
  budget : DecodeBudget,
) -> Bytes raise ParseError {
  self.read_string(
    limit,
    budget,
    allow_lzf=true,
    resource="stream-string-bytes",
  ).value
}

///|
fn Reader::read_stream_record(
  self : Reader,
  prefix : KeyPrefix,
  database : UInt64,
  max_string_bytes : Int32,
  max_packed_bytes : Int32,
  budget : DecodeBudget,
) -> StreamRecord raise ParseError {
  let key = self.read_string(
    max_string_bytes,
    budget,
    allow_lzf=true,
    resource="string-bytes",
  )
  let start = self.pos
  let entries = []
  let nodes = self.read_count()
  self.require(nodes)
  for _ in 0..<nodes.to_int() {
    let offset = self.pos
    let id = self.stream_string(16, budget)
    if id.length() != 16 {
      raise InvalidStream(offset~, reason="invalid node ID width")
    }
    let packed = self.stream_string(max_packed_bytes, budget)
    read_stream_node(id, packed, offset, max_string_bytes, budget, entries)
  }
  let length = self.read_count()
  if length != entries.length().to_uint64() {
    raise InvalidStream(offset=start, reason="stream length mismatch")
  }
  let last_generated_id = self.read_stream_metadata_id()
  let first_entry_id = self.read_stream_metadata_id()
  let max_deleted_entry_id = self.read_stream_metadata_id()
  let entries_added = self.read_count()
  let group_count = self.read_count()
  self.require(group_count)
  let groups = []
  let group_names : Map[Bytes, Unit] = Map([])
  for _ in 0..<group_count.to_int() {
    let offset = self.pos
    let name = self.stream_string(max_string_bytes, budget)
    if group_names.contains(name) {
      raise InvalidStream(offset~, reason="duplicate group name")
    }
    group_names[name] = ()

    let milliseconds = self.read_count()
    let sequence = self.read_count()
    let last_delivered_id = { milliseconds, sequence, }
    let entries_read = self.read_count().reinterpret_as_int64()
    let pending = self.read_count()
    self.require(pending)
    let unassigned : Map[(UInt64, UInt64), StreamPending] = Map([])
    for _ in 0..<pending.to_int() {
      let offset = self.pos
      let id = self.read_stream_id()
      let identity = (id.milliseconds, id.sequence)
      if unassigned.contains(identity) {
        raise InvalidStream(offset~, reason="duplicate group pending ID")
      }
      let delivery_time_ms = self.read_i64_le()
      let delivery_count = self.read_count()
      unassigned[identity] = { id, delivery_time_ms, delivery_count, }
    }
    let consumer_count = self.read_count()
    self.require(consumer_count)
    let consumers = []
    let names : Map[Bytes, Unit] = Map([])
    for _ in 0..<consumer_count.to_int() {
      let offset = self.pos
      let name = self.stream_string(max_string_bytes, budget)
      if names.contains(name) {
        raise InvalidStream(offset~, reason="duplicate consumer name")
      }
      names[name] = ()

      let seen_time_ms = self.read_i64_le()
      let active_time_ms = self.read_i64_le()
      let owned = self.read_count()
      self.require(owned)
      let consumer_pending = []
      for _ in 0..<owned.to_int() {
        let offset = self.pos
        let id = self.read_stream_id()
        let identity = (id.milliseconds, id.sequence)
        guard unassigned.get(identity) is Some(message) else {
          raise InvalidStream(
            offset~,
            reason="missing or already assigned group pending ID",
          )
        }
        consumer_pending.push(message)
        unassigned.remove(identity)
      }
      consumers.push({
        name,
        seen_time_ms,
        active_time_ms,
        pending: consumer_pending,
      })
    }
    if !unassigned.is_empty() {
      raise InvalidStream(offset=self.pos, reason="unassigned group pending ID")
    }
    groups.push({
      name,
      last_delivered_id,
      entries_read,
      consumers,
      pending_count: pending,
    })
  }
  budget.charge((self.pos - start).to_uint64(), start)
  {
    database,
    key: key.value,
    key_storage: key.storage,
    entries,
    length,
    last_generated_id,
    first_entry_id,
    max_deleted_entry_id,
    entries_added,
    group_count,
    groups,
    payload: self.input[start:self.pos].to_owned(),
    expires_at_ms: prefix.expires_at_ms,
    idle_seconds: prefix.idle_seconds,
    frequency: prefix.frequency,
    record_start: prefix.start,
    record_end: self.pos,
    serialized_bytes: (self.pos - prefix.start).to_uint64(),
  }
}

///|
pub(all) struct StreamEntry {
  milliseconds : UInt64
  sequence : UInt64
  fields : Array[HashEntry]
} derive(Debug, Eq)

///|
pub extend StreamEntry with @debug.Debug::{to_repr}

///|
pub extend StreamEntry with Eq::{equal, not_equal}

///|
fn Reader::read_stream_id(self : Reader) -> StreamMessageId raise ParseError {
  let milliseconds = self.read_unsigned(8, little_endian=false)
  let sequence = self.read_unsigned(8, little_endian=false)
  { milliseconds, sequence, }
}

///|
fn Reader::stream_integer(
  self : Reader,
  offset : Int32,
  budget : DecodeBudget,
) -> Int64 raise ParseError {
  let tag = self.lp_read(1UL, offset)[0].to_int()
  self.pos -= 1
  if !(tag < 128 || (tag >= 192 && tag < 224) || (tag >= 241 && tag <= 244)) {
    raise InvalidStream(offset~, reason="expected listpack integer")
  }
  let raw = self.read_listpack_entry(offset, 20, budget)
  let negative = raw[0] == b'-'
  let mut value = 0UL
  for i in (if negative { 1 } else { 0 })..<raw.length() {
    value = value * 10UL + (raw[i].to_int() - 48).to_uint64()
  }
  (if negative { 0UL - value } else { value }).reinterpret_as_int64()
}

///|
fn Reader::stream_node_count(
  self : Reader,
  offset : Int32,
  budget : DecodeBudget,
) -> Int32 raise ParseError {
  let count = self.stream_integer(offset, budget)
  if count < 0L || count > self.remaining().to_int64() {
    raise InvalidStream(offset~, reason="invalid stream listpack count")
  }
  count.to_int()
}

///|
fn read_stream_node(
  id : Bytes,
  packed : Bytes,
  offset : Int32,
  limit : Int32,
  budget : DecodeBudget,
  entries : Array[StreamEntry],
) -> Unit raise ParseError {
  let (reader, declared) = open_listpack(packed, offset)
  let live = reader.stream_node_count(offset, budget)
  let deleted = reader.stream_node_count(offset, budget)
  let field_count = reader.stream_node_count(offset, budget)
  let master = []
  for _ in 0..<field_count {
    master.push(reader.read_listpack_entry(offset, limit, budget))
  }
  if reader.stream_integer(offset, budget) != 0L {
    raise InvalidStream(offset~, reason="invalid master terminator")
  }
  let mut elements = 4 + field_count
  let mut actual_live = 0
  let key_reader = Reader::new(id, max_input_bytes=16)
  let milliseconds = key_reader.read_unsigned(8, little_endian=false)
  let sequence = key_reader.read_unsigned(8, little_endian=false)
  for _ in 0..<(live + deleted) {
    let flags = reader.stream_integer(offset, budget)
    if flags < 0L || flags > 3L {
      raise InvalidStream(offset~, reason="invalid stream entry flags")
    }
    let ms = milliseconds +
      reader.stream_integer(offset, budget).reinterpret_as_uint64()
    let seq = sequence +
      reader.stream_integer(offset, budget).reinterpret_as_uint64()
    let same = (flags & 2L) != 0L
    let names = if same {
      master
    } else {
      let count = reader.stream_node_count(offset, budget)
      let names = []
      for _ in 0..<count {
        names.push(reader.read_listpack_entry(offset, limit, budget))
      }
      names
    }
    let fields = []
    for field in names {
      let value = reader.read_listpack_entry(offset, limit, budget)
      fields.push({ field, value, })
    }
    let width = 3 + names.length() + (if same { 0 } else { 1 + names.length() })
    if reader.stream_integer(offset, budget) != width.to_int64() {
      raise InvalidStream(offset~, reason="invalid stream entry back count")
    }
    elements += width + 1
    if (flags & 1L) == 0L {
      if entries.last() is Some(previous) {
        if ms < previous.milliseconds ||
          (ms == previous.milliseconds && seq <= previous.sequence) {
          raise InvalidStream(
            offset~,
            reason="stream message IDs must increase",
          )
        }
      }
      actual_live += 1
      entries.push({ milliseconds: ms, sequence: seq, fields, })
    }
  }
  if actual_live != live ||
    reader.pos != packed.length() - 1 ||
    (declared != 65535 && declared != elements) {
    raise InvalidStream(offset~, reason="stream listpack count mismatch")
  }
}

///|
// Metadata IDs use two RDB lengths; node and PEL IDs use fixed-width bytes.
fn Reader::read_stream_metadata_id(
  self : Reader,
) -> StreamMessageId raise ParseError {
  let milliseconds = self.read_count()
  let sequence = self.read_count()
  { milliseconds, sequence, }
}
