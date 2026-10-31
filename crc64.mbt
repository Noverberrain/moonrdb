// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
// Independently implemented reflected CRC64 with Redis's polynomial.
// Reversing 0xad93d23594c935a9 gives 0x95ac9329ac4bc9b5.
// Initial value and final XOR are zero. Includes the EOF byte, excludes the
// eight checksum bytes. This simple bitwise implementation is not a benchmark.
fn crc64(input : BytesView) -> UInt64 {
  let mut crc = 0UL
  for byte in input {
    crc = crc ^ byte.to_uint64()
    for _ in 0..<8 {
      crc = if (crc & 1UL) == 0UL {
        crc >> 1
      } else {
        (crc >> 1) ^ 0x95ac9329ac4bc9b5UL
      }
    }
  }
  crc
}
