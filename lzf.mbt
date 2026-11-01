// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
// Independently implements LZF literal and back-reference tokens. The caller
// checks the output size against single-string and cumulative budgets first.
fn decompress_lzf(
  input : BytesView,
  output_size : Int32,
  base_offset : Int32,
) -> Bytes raise ParseError {
  let output : FixedArray[Byte] = FixedArray::make(output_size, 0)
  let mut pos = 0
  let mut written = 0
  while pos < input.length() {
    let token_offset = base_offset + pos
    let control = input[pos].to_int()
    pos += 1
    if control < 32 {
      let count = control + 1
      if count > input.length() - pos {
        raise InvalidLzf(offset=token_offset, reason="truncated literal")
      }
      if count > output_size - written {
        raise InvalidLzf(
          offset=token_offset,
          reason="literal exceeds output size",
        )
      }
      for i in 0..<count {
        output[written + i] = input[pos + i]
      }
      pos += count
      written += count
    } else {
      let mut count = control >> 5
      if count == 7 {
        if pos == input.length() {
          raise InvalidLzf(
            offset=token_offset,
            reason="missing extended match length",
          )
        }
        count += input[pos].to_int()
        pos += 1
      }
      if pos == input.length() {
        raise InvalidLzf(offset=token_offset, reason="missing match distance")
      }
      let distance = ((control & 31) << 8) + input[pos].to_int() + 1
      pos += 1
      count += 2
      if distance > written {
        raise InvalidLzf(offset=token_offset, reason="match precedes output")
      }
      if count > output_size - written {
        raise InvalidLzf(
          offset=token_offset,
          reason="match exceeds output size",
        )
      }
      // Forward byte copying deliberately permits overlapping matches.
      for i in 0..<count {
        output[written + i] = output[written + i - distance]
      }
      written += count
    }
  }
  if written != output_size {
    raise InvalidLzf(
      offset=base_offset + input.length(),
      reason="decoded size mismatch",
    )
  }
  Bytes::makei(output_size, i => output[i])
}
