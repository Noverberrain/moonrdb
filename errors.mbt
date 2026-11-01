// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
/// Offsets are zero-based byte offsets in the supplied input.
pub(all) suberror ParseError {
  InvalidInputLimit(offset~ : Int32, limit~ : Int32)
  InputTooLarge(offset~ : Int32, size~ : Int32, limit~ : Int32)
  UnexpectedEnd(offset~ : Int32, needed~ : UInt64, remaining~ : Int32)
  InvalidMagic(offset~ : Int32)
  InvalidVersionDigit(offset~ : Int32)
  UnsupportedVersion(offset~ : Int32, version~ : Int32)
  InvalidLengthTag(offset~ : Int32, tag~ : Byte)
  InvalidStringEncoding(offset~ : Int32, encoding~ : Int32)
  UnexpectedEncodedLength(offset~ : Int32)
  InvalidResourceLimit(offset~ : Int32, resource~ : String, limit~ : Int32)
  ResourceLimitExceeded(
    offset~ : Int32,
    resource~ : String,
    limit~ : UInt64,
    actual~ : UInt64
  )
  UnsupportedStringEncoding(offset~ : Int32, encoding~ : Int32)
  UnsupportedObjectType(offset~ : Int32, object_type~ : Byte)
  UnsupportedOpcode(offset~ : Int32, opcode~ : Byte)
  DuplicateKeyMetadata(offset~ : Int32, opcode~ : Byte)
  DanglingKeyMetadata(offset~ : Int32)
  ChecksumMismatch(offset~ : Int32, stored~ : UInt64, computed~ : UInt64)
  TrailingData(offset~ : Int32, remaining~ : Int32)
  InvalidLzf(offset~ : Int32, reason~ : String)
  InvalidHash(offset~ : Int32, reason~ : String)
  InvalidListpack(offset~ : Int32, inner_offset~ : Int32, reason~ : String)
} derive(Debug)

///|
pub extend ParseError with @debug.Debug::{to_repr}
