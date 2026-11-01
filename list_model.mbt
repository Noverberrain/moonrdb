// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
pub(all) enum ListNodeContainer {
  Plain
  Packed
} derive(Debug, Eq)

///|
pub extend ListNodeContainer with @debug.Debug::{to_repr}

///|
pub extend ListNodeContainer with Eq::{equal, not_equal}

///|
/// Node ranges refer to the original file and include container and RDB string.
/// Item ranges index ListRecord.items; no decoded payload is duplicated here.
pub(all) struct ListNode {
  container : ListNodeContainer
  storage : StringStorage
  item_start : Int32
  item_end : Int32
  node_start : Int32
  node_end : Int32
} derive(Debug, Eq)

///|
pub extend ListNode with @debug.Debug::{to_repr}

///|
pub extend ListNode with Eq::{equal, not_equal}

///|
/// RDB type 18 (quicklist2). Ordered binary items, including duplicates and
/// empty packed entries. Legacy List encodings are not supported.
pub(all) struct ListRecord {
  database : UInt64
  key : Bytes
  key_storage : StringStorage
  items : Array[Bytes]
  nodes : Array[ListNode]
  expires_at_ms : Int64?
  idle_seconds : UInt64?
  frequency : Byte?
  record_start : Int32
  record_end : Int32
  serialized_bytes : UInt64
} derive(Debug, Eq)

///|
pub extend ListRecord with @debug.Debug::{to_repr}

///|
pub extend ListRecord with Eq::{equal, not_equal}
