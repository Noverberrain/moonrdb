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
