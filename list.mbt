// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
priv struct ListBudget {
  max_nodes : Int32
  max_items : Int32
  mut nodes : Int32
  mut items : Int32
}

///|
fn ListBudget::check_items(
  self : ListBudget,
  count : UInt64,
  offset : Int32,
) -> Unit raise ParseError {
  // Bound the request before adding to the global count (avoids UInt64 wrap).
  check_resource_limit("list-items", offset, count, self.max_items)
  check_resource_limit(
    "list-items",
    offset,
    self.items.to_uint64() + count,
    self.max_items,
  )
}

///|
fn ListBudget::charge_items(
  self : ListBudget,
  count : UInt64,
  offset : Int32,
) -> Unit raise ParseError {
  self.check_items(count, offset)
  self.items += count.to_int()
}

///|
fn ListBudget::charge_nodes(
  self : ListBudget,
  count : UInt64,
  offset : Int32,
) -> Unit raise ParseError {
  check_resource_limit("list-nodes", offset, count, self.max_nodes)
  check_resource_limit(
    "list-nodes",
    offset,
    self.nodes.to_uint64() + count,
    self.max_nodes,
  )
  self.nodes += count.to_int()
}

///|
fn decode_list_items(
  input : Bytes,
  base : Int32,
  max_string_bytes : Int32,
  budget : DecodeBudget,
  lists : ListBudget,
) -> Array[Bytes] raise ParseError {
  let (reader, declared) = open_listpack(input, base)
  if declared != 65535 {
    lists.check_items(declared.to_uint64(), base)
  }
  let items = []
  while reader.pos < input.length() - 1 {
    lists.charge_items(1UL, base)
    items.push(reader.read_listpack_entry(base, max_string_bytes, budget))
  }
  if declared != 65535 && declared != items.length() {
    raise InvalidListpack(
      offset=base,
      inner_offset=4,
      reason="element count mismatch",
    )
  }
  if items.is_empty() {
    raise InvalidList(offset=base, reason="empty packed node")
  }
  items
}

///|
fn Reader::read_list_record(
  self : Reader,
  prefix : KeyPrefix,
  database : UInt64,
  max_string_bytes : Int32,
  max_packed_bytes : Int32,
  budget : DecodeBudget,
  lists : ListBudget,
) -> ListRecord raise ParseError {
  let key = self.read_string(
    max_string_bytes,
    budget,
    allow_lzf=true,
    resource="string-bytes",
  )
  let count_offset = self.pos
  let node_count = self.read_count()
  lists.charge_nodes(node_count, count_offset)
  if node_count == 0UL {
    raise InvalidList(offset=count_offset, reason="empty quicklist")
  }
  let items = []
  let nodes = []
  for _ in 0..<node_count.to_int() {
    let node_start = self.pos
    let container = self.read_count()
    let base = self.pos
    let item_start = items.length()
    let (kind, storage) : (ListNodeContainer, StringStorage) = match container {
      1UL => {
        lists.charge_items(1UL, base)
        let value = self.read_string(
          max_string_bytes,
          budget,
          allow_lzf=true,
          resource="string-bytes",
        )
        if value.value.is_empty() {
          raise InvalidList(offset=base, reason="empty plain node")
        }
        items.push(value.value)
        (Plain, value.storage)
      }
      2UL => {
        let scratch : DecodeBudget = { limit: max_packed_bytes, used: 0, }
        let packed = self.read_string(
          max_packed_bytes,
          scratch,
          allow_lzf=true,
          resource="packed-bytes",
        )
        for
          value in decode_list_items(
            packed.value,
            base,
            max_string_bytes,
            budget,
            lists,
          ) {
          items.push(value)
        }
        (Packed, packed.storage)
      }
      _ =>
        raise InvalidList(
          offset=node_start,
          reason="unknown quicklist container",
        )
    }
    nodes.push({
      container: kind,
      storage,
      item_start,
      item_end: items.length(),
      node_start,
      node_end: self.pos,
    })
  }
  {
    database,
    key: key.value,
    key_storage: key.storage,
    items,
    nodes,
    expires_at_ms: prefix.expires_at_ms,
    idle_seconds: prefix.idle_seconds,
    frequency: prefix.frequency,
    record_start: prefix.start,
    record_end: self.pos,
    serialized_bytes: (self.pos - prefix.start).to_uint64(),
  }
}
