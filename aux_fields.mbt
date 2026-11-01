// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn Reader::read_aux_string(
  self : Reader,
  max_string_bytes : Int32,
  budget : DecodeBudget,
  allow_lzf~ : Bool,
) -> Bytes raise ParseError {
  self.read_string(
    max_string_bytes,
    budget,
    allow_lzf~,
    resource="aux-string-bytes",
  ).value
}

///|
fn check_resource_limit(
  resource : String,
  offset : Int32,
  actual : UInt64,
  limit : Int32,
) -> Unit raise ParseError {
  if actual > limit.to_uint64() {
    raise ResourceLimitExceeded(
      offset~,
      resource~,
      actual~,
      limit=limit.to_uint64(),
    )
  }
}
