// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
priv struct SetBudget {
  limit : Int32
  mut used : Int32
}

///|
fn SetBudget::check(
  self : SetBudget,
  count : UInt64,
  offset : Int32,
) -> Unit raise ParseError {
  check_resource_limit("set-members", offset, count, self.limit)
  check_resource_limit(
    "set-members",
    offset,
    self.used.to_uint64() + count,
    self.limit,
  )
}

///|
fn SetBudget::charge(
  self : SetBudget,
  count : UInt64,
  offset : Int32,
) -> Unit raise ParseError {
  self.check(count, offset)
  self.used += count.to_int()
}

///|
fn decode_set_listpack(
  input : Bytes,
  base : Int32,
  max_string_bytes : Int32,
  budget : DecodeBudget,
  sets : SetBudget,
) -> Array[Bytes] raise ParseError {
  let (reader, declared) = open_listpack(input, base)
  if declared != 65535 {
    sets.check(declared.to_uint64(), base)
  }
  let members = []
  let seen : Map[Bytes, Unit] = Map([])
  while reader.pos < input.length() - 1 {
    sets.charge(1UL, base)
    let element = reader.read_listpack_entry(base, max_string_bytes, budget)
    if seen.contains(element) {
      raise InvalidSet(offset=base, reason="duplicate member")
    }
    seen[element] = ()
    members.push(element)
  }
  if declared != 65535 && declared != members.length() {
    raise InvalidListpack(
      offset=base,
      inner_offset=4,
      reason="element count mismatch",
    )
  }
  if members.is_empty() {
    raise InvalidSet(offset=base, reason="empty set")
  }
  members
}

///|
fn Reader::read_set_record(
  self : Reader,
  prefix : KeyPrefix,
  database : UInt64,
  max_string_bytes : Int32,
  max_packed_bytes : Int32,
  budget : DecodeBudget,
  sets : SetBudget,
) -> SetRecord raise ParseError {
  let key = self.read_string(
    max_string_bytes,
    budget,
    allow_lzf=true,
    resource="string-bytes",
  )
  let offset = self.pos
  let (members, storage, packed_storage) : (
    Array[Bytes],
    SetStorage,
    StringStorage?,
  ) = match prefix.object_type.to_int() {
    2 => {
      let count = self.read_count()
      sets.charge(count, offset)
      if count == 0UL {
        raise InvalidSet(offset~, reason="empty set")
      }
      let members = []
      let seen : Map[Bytes, Unit] = Map([])
      for _ in 0..<count.to_int() {
        let member_offset = self.pos
        let element = self.read_string(
            max_string_bytes,
            budget,
            allow_lzf=true,
            resource="string-bytes",
          ).value
        if seen.contains(element) {
          raise InvalidSet(offset=member_offset, reason="duplicate member")
        }
        seen[element] = ()
        members.push(element)
      }
      (members, Hashtable, None)
    }
    value => {
      let scratch : DecodeBudget = { limit: max_packed_bytes, used: 0, }
      let packed = self.read_string(
        max_packed_bytes,
        scratch,
        allow_lzf=true,
        resource="packed-bytes",
      )
      if value == 11 {
        let (members, width) = decode_intset(
          packed.value,
          offset,
          max_string_bytes,
          budget,
          sets,
        )
        (members, Intset(width), Some(packed.storage))
      } else {
        (
          decode_set_listpack(
            packed.value,
            offset,
            max_string_bytes,
            budget,
            sets,
          ),
          Listpack,
          Some(packed.storage),
        )
      }
    }
  }
  {
    database,
    key: key.value,
    key_storage: key.storage,
    members,
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
