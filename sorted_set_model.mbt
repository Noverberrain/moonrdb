// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
pub(all) enum SortedSetStorage {
  BinaryDouble
  Listpack
} derive(Debug, Eq)

///|
pub extend SortedSetStorage with @debug.Debug::{to_repr}

///|
pub extend SortedSetStorage with Eq::{equal, not_equal}

///|
/// Entries retain wire order, which is not guaranteed to be score order.
pub(all) struct SortedSetRecord {
  database : UInt64
  key : Bytes
  key_storage : StringStorage
  entries : Array[SortedSetEntry]
  storage : SortedSetStorage
  packed_storage : StringStorage?
  expires_at_ms : Int64?
  idle_seconds : UInt64?
  frequency : Byte?
  record_start : Int32
  record_end : Int32
  serialized_bytes : UInt64
} derive(Debug, Eq)

///|
pub extend SortedSetRecord with @debug.Debug::{to_repr}

///|
pub extend SortedSetRecord with Eq::{equal, not_equal}

///|
pub(all) struct SortedSetEntry {
  element : Bytes
  score : Double
} derive(Debug, Eq)

///|
pub extend SortedSetEntry with @debug.Debug::{to_repr}

///|
pub extend SortedSetEntry with Eq::{equal, not_equal}
