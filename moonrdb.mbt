// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
/// Read only the nine-byte RDB header, accepting format version 11.
/// The rest of the file is not parsed or checked. The limit applies to the
/// entire supplied input and does not undo its allocation by the caller.
///
/// ```mbt check
/// test {
///   assert_eq(@moonrdb.read_header(b"REDIS0011"), 11)
/// }
/// ```
pub fn read_header(
  input : Bytes,
  max_input_bytes~ : Int32 = 64 * 1024 * 1024,
) -> Int32 raise ParseError {
  Reader::new(input, max_input_bytes~).read_header()
}
