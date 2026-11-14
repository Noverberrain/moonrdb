// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
pub(all) struct StreamRecord {
  database : UInt64
  key : Bytes
  key_storage : StringStorage
  entries : Array[StreamEntry]
  length : UInt64
  group_count : UInt64
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
  // Last ID, first ID, maximal deleted ID, and lifetime entries added.
  for _ in 0..<7 {
    ignore(self.read_count())
  }
  let group_count = self.read_count()
  self.require(group_count)
  let groups : Map[Bytes, Unit] = Map([])
  for _ in 0..<group_count.to_int() {
    let offset = self.pos
    let name = self.stream_string(max_string_bytes, budget)
    if groups.contains(name) {
      raise InvalidStream(offset~, reason="duplicate group name")
    }
    groups[name] = ()

    for _ in 0..<3 {
      ignore(self.read_count())
    }
    let pending = self.read_count()
    self.require(pending)
    let unassigned : Map[Bytes, Unit] = Map([])
    for _ in 0..<pending.to_int() {
      let offset = self.pos
      let id = self.read_bytes(16UL).to_owned()
      if unassigned.contains(id) {
        raise InvalidStream(offset~, reason="duplicate group pending ID")
      }
      unassigned[id] = ()
      ignore(self.read_bytes(8UL))
      ignore(self.read_count())
    }
    let consumers = self.read_count()
    self.require(consumers)
    let names : Map[Bytes, Unit] = Map([])
    for _ in 0..<consumers.to_int() {
      let offset = self.pos
      let name = self.stream_string(max_string_bytes, budget)
      if names.contains(name) {
        raise InvalidStream(offset~, reason="duplicate consumer name")
      }
      names[name] = ()

      ignore(self.read_bytes(16UL))
      let owned = self.read_count()
      self.require(owned)
      for _ in 0..<owned.to_int() {
        let offset = self.pos
        let id = self.read_bytes(16UL).to_owned()
        if !unassigned.contains(id) {
          raise InvalidStream(
            offset~,
            reason="missing or already assigned group pending ID",
          )
        }
        unassigned.remove(id)
      }
    }
    if !unassigned.is_empty() {
      raise InvalidStream(offset=self.pos, reason="unassigned group pending ID")
    }
  }
  budget.charge((self.pos - start).to_uint64(), start)
  {
    database,
    key: key.value,
    key_storage: key.storage,
    entries,
    length,
    group_count,
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
