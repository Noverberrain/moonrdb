// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
pub(all) enum Command {
  Help
  Stats(path~ : String, max_input_bytes~ : Int32)
  Inspect(path~ : String, max_input_bytes~ : Int32)
} derive(Debug, Eq)

///|
pub extend Command with @debug.Debug::{to_repr}

///|
pub extend Command with Eq::{equal, not_equal}

///|
pub(all) suberror UsageError {
  InvalidArguments
} derive(Debug)

///|
pub extend UsageError with @debug.Debug::{to_repr}

///|
pub fn usage() -> String {
  let text =
    #|Usage: moonrdb inspect <file.rdb> [--max-input-bytes <bytes>]
    #|       moonrdb stats <file.rdb> [--max-input-bytes <bytes>]
    #|       moonrdb --help
    #|
    #|Inspect a complete format-11 RDB snapshot (Redis 7.2.5 supported encodings).
    #|--max-input-bytes: positive decimal integer, default 67108864 (64 MiB).
    #|Use -- before a file name beginning with '-'. Regular files only.
    #|Other parser limits keep their library defaults; see docs/inspect.md.
    #|Exit codes: 0 success, 1 input/read/parse failure, 2 invalid arguments.
    #|Checksum disabled is reported separately and does not mean validated CRC64.
    #|
  text
}

///|
// Do not inherit parse_int's broader sign/radix/underscore syntax.
fn positive_limit(text : String) -> Int32 raise UsageError {
  if text.is_empty() {
    raise InvalidArguments
  }
  let mut value = 0
  for c in text {
    if c < '0' || c > '9' {
      raise InvalidArguments
    }
    let digit = c.to_int() - 48
    if value > (2147483647 - digit) / 10 {
      raise InvalidArguments
    }
    value = value * 10 + digit
  }
  if value == 0 {
    raise InvalidArguments
  }
  value
}

///|
/// Arguments exclude the executable name. A single file, no silent options.
pub fn parse_args(args : ArrayView[String]) -> Command raise UsageError {
  match args {
    ["--help"] | ["-h"] | ["inspect", "--help"] | ["inspect", "-h"] => Help
    [name, .. rest] if name == "inspect" || name == "stats" => {
      let mut path : String? = None
      let mut limit = 64 * 1024 * 1024
      let mut has_limit = false
      let mut options = true
      for remaining = rest {
        match remaining {
          [] => break
          ["--", .. tail] if options => {
            options = false
            continue tail
          }
          ["--max-input-bytes", value, .. tail] if options && !has_limit => {
            limit = positive_limit(value)
            has_limit = true
            continue tail
          }
          [value, .. tail] => {
            if value.is_empty() ||
              (options && value.has_prefix("-")) ||
              path is Some(_) {
              raise InvalidArguments
            }
            path = Some(value)
            continue tail
          }
        }
      }
      guard path is Some(path) else { raise InvalidArguments }
      if name == "stats" {
        Stats(path~, max_input_bytes=limit)
      } else {
        Inspect(path~, max_input_bytes=limit)
      }
    }
    _ => raise InvalidArguments
  }
}
