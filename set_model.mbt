// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
pub(all) enum SetStorage {
  Hashtable
  Intset(Int32)
  Listpack
} derive(Debug, Eq)

///|
pub extend SetStorage with @debug.Debug::{to_repr}

///|
pub extend SetStorage with Eq::{equal, not_equal}

///|
/// Members retain input order, not semantic Set ordering. Intset storage records
/// the element width in bytes (2, 4 or 8). Packed storage describes the outer
/// RDB string for intset/listpack only. Binary values are never UTF-8 replaced.
pub(all) struct SetRecord {
  database : UInt64
  key : Bytes
  key_storage : StringStorage
  members : Array[Bytes]
  storage : SetStorage
  packed_storage : StringStorage?
  expires_at_ms : Int64?
  idle_seconds : UInt64?
  frequency : Byte?
  record_start : Int32
  record_end : Int32
  serialized_bytes : UInt64
} derive(Debug, Eq)

///|
pub extend SetRecord with @debug.Debug::{to_repr}

///|
pub extend SetRecord with Eq::{equal, not_equal}
