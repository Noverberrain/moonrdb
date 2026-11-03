// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
pub(all) enum Command {
  Help
  Export(
    path~ : String,
    max_input_bytes~ : Int32,
    db~ : UInt64?,
    prefix~ : String?,
    output~ : String?
  )
  Top(path~ : String, max_input_bytes~ : Int32, limit~ : Int32)
  Stats(
    path~ : String,
    max_input_bytes~ : Int32,
    at_ms~ : Int64?,
    prefixes~ : Array[String]
  )
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
    #|       stats options: [--at YYYY-MM-DDTHH:MM:SS[.sss]Z] [--prefix <UTF-8 text>]...
    #|       moonrdb top <file.rdb> [--by serialized-bytes] [--limit <1..10000>]
    #|       moonrdb export <file.rdb> [--db <id>] [--prefix <UTF-8 text>] [--format jsonl] [--output <file>]
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
    ["--help"]
    | ["-h"]
    | ["inspect", "--help"]
    | ["inspect", "-h"]
    | ["stats", "--help"]
    | ["stats", "-h"]
    | ["top", "--help"]
    | ["top", "-h"]
    | ["export", "--help"]
    | ["export", "-h"] => Help
    [name, .. rest] if name == "inspect" ||
      name == "stats" ||
      name == "top" ||
      name == "export" => {
      let mut path : String? = None
      let mut limit = 64 * 1024 * 1024
      let mut has_limit = false
      let mut top_limit = 20
      let mut has_top_limit = false
      let mut has_by = false
      let mut db : UInt64? = None
      let mut output : String? = None
      let mut has_format = false
      let mut at_ms : Int64? = None
      let prefixes : Array[String] = []
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
          ["--at", value, .. tail] if options &&
            name == "stats" &&
            at_ms is None => {
            at_ms = Some(parse_at(value))
            continue tail
          }
          ["--prefix", value, .. tail] if options &&
            (name == "stats" || name == "export") => {
            if name == "export" && !prefixes.is_empty() {
              raise InvalidArguments
            }
            if prefixes.contains(value) || prefixes.length() >= 64 {
              raise InvalidArguments
            }
            prefixes.push(value)
            continue tail
          }
          ["--limit", value, .. tail] if options &&
            name == "top" &&
            !has_top_limit => {
            top_limit = positive_limit(value)
            if top_limit > 10000 {
              raise InvalidArguments
            }
            has_top_limit = true
            continue tail
          }
          ["--by", "serialized-bytes", .. tail] if options &&
            name == "top" &&
            !has_by => {
            has_by = true
            continue tail
          }
          ["--db", value, .. tail] if options && name == "export" && db is None => {
            db = Some(database_number(value))
            continue tail
          }
          ["--output", value, .. tail] if options &&
            name == "export" &&
            output is None => {
            if value.is_empty() || value == "-" {
              raise InvalidArguments
            }
            output = Some(value)
            continue tail
          }
          ["--format", "jsonl", .. tail] if options &&
            name == "export" &&
            !has_format => {
            has_format = true
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
      if name == "export" {
        Export(
          path~,
          max_input_bytes=limit,
          db~,
          prefix=prefixes.get(0),
          output~,
        )
      } else if name == "top" {
        Top(path~, max_input_bytes=limit, limit=top_limit)
      } else if name == "stats" {
        Stats(path~, max_input_bytes=limit, at_ms~, prefixes~)
      } else {
        Inspect(path~, max_input_bytes=limit)
      }
    }
    _ => raise InvalidArguments
  }
}

///|
fn database_number(text : String) -> UInt64 raise UsageError {
  if text.is_empty() {
    raise InvalidArguments
  }
  let mut result = 0UL
  for c in text {
    if c < '0' || c > '9' {
      raise InvalidArguments
    }
    let digit = (c.to_int() - 48).to_uint64()
    if result > (0xffffffffffffffffUL - digit) / 10UL {
      raise InvalidArguments
    }
    result = result * 10UL + digit
  }
  result
}
