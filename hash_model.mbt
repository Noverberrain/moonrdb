// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
pub(all) enum HashStorage {
  Hashtable
  Listpack
} derive(Debug, Eq)

///|
pub extend HashStorage with @debug.Debug::{to_repr}

///|
pub extend HashStorage with Eq::{equal, not_equal}

///|
pub(all) struct HashEntry {
  field : Bytes
  value : Bytes
} derive(Debug, Eq)

///|
pub extend HashEntry with @debug.Debug::{to_repr}

///|
pub extend HashEntry with Eq::{equal, not_equal}

///|
/// Fields retain wire order, not a semantic ordering of the Hash.
/// packed_storage describes the outer RDB string only for listpack objects.
pub(all) struct HashRecord {
  database : UInt64
  key : Bytes
  key_storage : StringStorage
  entries : Array[HashEntry]
  storage : HashStorage
  packed_storage : StringStorage?
  expires_at_ms : Int64?
  idle_seconds : UInt64?
  frequency : Byte?
  record_start : Int32
  record_end : Int32
  serialized_bytes : UInt64
} derive(Debug, Eq)

///|
pub extend HashRecord with @debug.Debug::{to_repr}

///|
pub extend HashRecord with Eq::{equal, not_equal}

///|
pub(all) enum RdbRecord {
  String(StringRecord)
  Hash(HashRecord)
} derive(Debug, Eq)

///|
pub extend RdbRecord with @debug.Debug::{to_repr}

///|
pub extend RdbRecord with Eq::{equal, not_equal}

///|
/// Complete snapshot restricted to the explicitly supported object encodings.
pub(all) struct Snapshot {
  format_version : Int32
  aux_fields : Array[AuxField]
  database_selections : Array[UInt64]
  resize_hints : Array[DatabaseSizeHint]
  records : Array[RdbRecord]
  checksum : ChecksumStatus
  file_size : Int32
  global_overhead_bytes : UInt64
} derive(Debug, Eq)

///|
pub extend Snapshot with @debug.Debug::{to_repr}

///|
pub extend Snapshot with Eq::{equal, not_equal}
