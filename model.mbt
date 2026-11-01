// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
/// A zero stored checksum means disabled, never validated.
pub(all) enum ChecksumStatus {
  Valid(UInt64)
  Disabled
} derive(Debug, Eq)

///|
pub extend ChecksumStatus with @debug.Debug::{to_repr}

///|
pub extend ChecksumStatus with Eq::{equal, not_equal}

///|
/// Raw binary AUX key and value. Integer-encoded values are decimal bytes.
pub(all) struct AuxField {
  key : Bytes
  value : Bytes
} derive(Debug, Eq)

///|
pub extend AuxField with @debug.Debug::{to_repr}

///|
pub extend AuxField with Eq::{equal, not_equal}

///|
/// RESIZEDB values are allocation hints, not measured key counts.
pub(all) struct DatabaseSizeHint {
  database : UInt64
  keys : UInt64
  expires : UInt64
} derive(Debug, Eq)

///|
pub extend DatabaseSizeHint with @debug.Debug::{to_repr}

///|
pub extend DatabaseSizeHint with Eq::{equal, not_equal}

///|
/// A complete version-11 file containing no objects. Explicit selections and
/// hints retain input order, including duplicates. No implicit DB is listed.
pub(all) struct EmptySnapshot {
  format_version : Int32
  aux_fields : Array[AuxField]
  database_selections : Array[UInt64]
  resize_hints : Array[DatabaseSizeHint]
  checksum : ChecksumStatus
  file_size : Int32
} derive(Debug, Eq)

///|
pub extend EmptySnapshot with @debug.Debug::{to_repr}

///|
pub extend EmptySnapshot with Eq::{equal, not_equal}

///|
/// The actual string representation in the input, independently for key/value.
pub(all) enum StringStorage {
  Raw
  Integer8
  Integer16
  Integer32
  Lzf
} derive(Debug, Eq)

///|
pub extend StringStorage with @debug.Debug::{to_repr}

///|
pub extend StringStorage with Eq::{equal, not_equal}

///|
/// Binary-safe String record. The half-open range includes key metadata,
/// object type, key and value as serialized, including compressed bytes.
pub(all) struct StringRecord {
  database : UInt64
  key : Bytes
  value : Bytes
  key_storage : StringStorage
  value_storage : StringStorage
  expires_at_ms : Int64?
  idle_seconds : UInt64?
  frequency : Byte?
  record_start : Int32
  record_end : Int32
  serialized_bytes : UInt64
} derive(Debug, Eq)

///|
pub extend StringRecord with @debug.Debug::{to_repr}

///|
pub extend StringRecord with Eq::{equal, not_equal}

///|
/// Complete snapshot restricted to String objects. Records preserve file order;
/// no expiry filtering, duplicate-key replacement or clock-dependent behavior.
pub(all) struct StringSnapshot {
  format_version : Int32
  aux_fields : Array[AuxField]
  database_selections : Array[UInt64]
  resize_hints : Array[DatabaseSizeHint]
  records : Array[StringRecord]
  checksum : ChecksumStatus
  file_size : Int32
  global_overhead_bytes : UInt64
} derive(Debug, Eq)

///|
pub extend StringSnapshot with @debug.Debug::{to_repr}

///|
pub extend StringSnapshot with Eq::{equal, not_equal}
