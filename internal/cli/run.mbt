// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
priv suberror InputError {
  NotRegularFile
  InputLimit(size~ : Int64, limit~ : Int32)
  FileChanged
} derive(Debug)

///|
// Check the size on the open handle before allocating. Read exactly that size
// and probe for growth. This is bounded whole-file input, not a streaming parser.
async fn read_input(path : String, limit : Int32) -> Bytes {
  if @fs.kind(path[:]) != Regular {
    raise NotRegularFile
  }
  let file = @fs.open(path[:], mode=ReadOnly)
  defer file.close()
  if file.kind() != Regular {
    raise NotRegularFile
  }
  let size = file.size()
  if size < 0L || size > limit.to_int64() {
    raise InputLimit(size~, limit~)
  }
  let input = file.read_exactly(size.to_int())
  let probe = FixedArray::make(1, b'\x00')
  if file.read_into(probe, max_len=1) != 0 {
    raise FileChanged
  }
  input
}

///|
/// Run one command; stdout is written only after complete parsing succeeds.
pub async fn run(args : ArrayView[String]) -> Int32 {
  let command = parse_args(args) catch {
    _ => {
      @stdio.stderr.text.write("moonrdb: invalid arguments\n" + usage())
      return 2
    }
  }
  match command {
    Help => {
      @stdio.stdout.text.write(usage())
      0
    }
    Inspect(path~, max_input_bytes~) | Stats(path~, max_input_bytes~) => {
      let input = read_input(path, max_input_bytes) catch {
        InputLimit(size~, limit~) => {
          @stdio.stderr.text.write(
            "moonrdb: input exceeds byte limit (size=\{size}, limit=\{limit})\n",
          )
          return 1
        }
        NotRegularFile => {
          @stdio.stderr.text.write("moonrdb: input must be a regular file\n")
          return 1
        }
        FileChanged => {
          @stdio.stderr.text.write(
            "moonrdb: input grew during reading; retry with a stable file\n",
          )
          return 1
        }
        _ => {
          @stdio.stderr.text.write("moonrdb: unable to read input file\n")
          return 1
        }
      }
      let snapshot = @moonrdb.parse(input, max_input_bytes~) catch {
        error => {
          @stdio.stderr.text.write("moonrdb: parse failed: \{repr(error)}\n")
          return 1
        }
      }
      @stdio.stdout.text.write(
        if command is Stats(..) {
          stats_report(snapshot)
        } else {
          inspect_report(snapshot)
        },
      )
      0
    }
  }
}
