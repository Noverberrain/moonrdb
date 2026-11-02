// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
priv struct SortedSetBudget {
  limit : Int32
  mut used : Int32
}

///|
fn SortedSetBudget::check(
  self : SortedSetBudget,
  count : UInt64,
  offset : Int32,
) -> Unit raise ParseError {
  check_resource_limit("sorted-set-entries", offset, count, self.limit)
  check_resource_limit(
    "sorted-set-entries",
    offset,
    self.used.to_uint64() + count,
    self.limit,
  )
}

///|
fn SortedSetBudget::charge(
  self : SortedSetBudget,
  count : UInt64,
  offset : Int32,
) -> Unit raise ParseError {
  self.check(count, offset)
  self.used += count.to_int()
}

///|
// Only decimal ASCII and explicit infinities; reject NaN, whitespace, NUL and
// implementation-specific syntax. Scratch score text is bounded independently.
fn parse_sorted_set_score(
  raw : Bytes,
  offset : Int32,
) -> Double raise ParseError {
  let invalid = InvalidSortedSet(offset~, reason="invalid score")
  if raw == b"inf" || raw == b"+inf" {
    return 0x7ff0000000000000UL.reinterpret_as_double()
  }
  if raw == b"-inf" {
    return 0xfff0000000000000UL.reinterpret_as_double()
  }
  if raw.is_empty() {
    raise invalid
  }
  let chars : Array[Char] = []
  for byte in raw {
    let n = byte.to_int()
    if !((n >= 48 && n <= 57) ||
      n == 43 ||
      n == 45 ||
      n == 46 ||
      n == 101 ||
      n == 69) {
      raise invalid
    }
    guard n.to_char() is Some(c) else { raise invalid }
    chars.push(c)
  }
  let text = String::from_array(chars)
  let score = @string.parse_double(text[:]) catch { _ => raise invalid }
  if score.is_nan() || score.is_inf() {
    raise invalid
  }
  score
}

///|
fn Reader::read_sorted_set_record(
  self : Reader,
  prefix : KeyPrefix,
  database : UInt64,
  max_string_bytes : Int32,
  max_packed_bytes : Int32,
  budget : DecodeBudget,
  sorted_sets : SortedSetBudget,
) -> SortedSetRecord raise ParseError {
  let key = self.read_string(
    max_string_bytes,
    budget,
    allow_lzf=true,
    resource="string-bytes",
  )
  let base = self.pos
  let entries : Array[SortedSetEntry] = []
  let seen : Map[Bytes, Unit] = Map([])
  let (storage, packed_storage) : (SortedSetStorage, StringStorage?) = if prefix.object_type ==
    b'\x05' {
    let count = self.read_count()
    sorted_sets.charge(count, base)
    for _ in 0..<count.to_int() {
      let offset = self.pos
      let element = self.read_string(
          max_string_bytes,
          budget,
          allow_lzf=true,
          resource="string-bytes",
        ).value
      let score = self.read_u64_le().reinterpret_as_double()
      if score.is_nan() {
        raise InvalidSortedSet(offset~, reason="NaN score")
      }
      if seen.contains(element) {
        raise InvalidSortedSet(offset~, reason="duplicate member")
      }
      seen[element] = ()
      entries.push({ element, score, })
    }
    (BinaryDouble, None)
  } else {
    let scratch : DecodeBudget = { limit: max_packed_bytes, used: 0, }
    let packed = self.read_string(
      max_packed_bytes,
      scratch,
      allow_lzf=true,
      resource="packed-bytes",
    )
    let (reader, declared) = open_listpack(packed.value, base)
    if declared != 65535 {
      if declared % 2 != 0 {
        raise InvalidSortedSet(offset=base, reason="odd listpack element count")
      }
      sorted_sets.check((declared / 2).to_uint64(), base)
    }
    while reader.pos < packed.value.length() - 1 {
      sorted_sets.charge(1UL, base)
      let element = reader.read_listpack_entry(base, max_string_bytes, budget)
      if reader.pos == packed.value.length() - 1 {
        raise InvalidSortedSet(offset=base, reason="odd listpack element count")
      }
      let score_budget : DecodeBudget = { limit: 128, used: 0, }
      let raw = reader.read_listpack_entry(base, 128, score_budget)
      let score = parse_sorted_set_score(raw, base)
      if seen.contains(element) {
        raise InvalidSortedSet(offset=base, reason="duplicate member")
      }
      if entries.last() is Some(previous) {
        if score < previous.score ||
          (score == previous.score && element.compare(previous.element) <= 0) {
          raise InvalidSortedSet(offset=base, reason="unordered listpack")
        }
      }
      seen[element] = ()
      entries.push({ element, score, })
    }
    if declared != 65535 && declared != entries.length() * 2 {
      raise InvalidListpack(
        offset=base,
        inner_offset=4,
        reason="element count mismatch",
      )
    }
    (Listpack, Some(packed.storage))
  }
  if entries.is_empty() {
    raise InvalidSortedSet(offset=base, reason="empty sorted set")
  }
  {
    database,
    key: key.value,
    key_storage: key.storage,
    entries,
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
