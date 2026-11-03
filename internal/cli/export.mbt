// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn export_match(
  record : @moonrdb.RdbRecord,
  db : UInt64?,
  prefix : Bytes?,
) -> Bool {
  let (database, key, _, _, _, _, _, _) = top_meta(record)
  if db is Some(id) && database != id {
    return false
  }
  if prefix is Some(bytes) && !bytes_prefix(key, bytes) {
    return false
  }
  true
}

///|
async fn write_records(
  snapshot : @moonrdb.Snapshot,
  db : UInt64?,
  prefix : Bytes?,
  write : async (String) -> Unit,
) -> Int32 {
  let mut count = 0
  for record in snapshot.records {
    if export_match(record, db, prefix) {
      write(record_json(record).stringify() + "\n")
      count += 1
    }
  }
  count
}

///|
async fn export_snapshot(
  snapshot : @moonrdb.Snapshot,
  input : String,
  db : UInt64?,
  prefix : String?,
  output : String?,
) -> Unit {
  let encoded = prefix.map(p => @utf8.encode(p[:]))
  let count = if output is Some(target) {
    let source = @fs.realpath(input[:])
    if @fs.exists(target[:]) {
      let destination = @fs.realpath(target[:])
      if source.to_lower() == destination.to_lower() {
        fail("input and output must differ")
      }
    }
    guard @env.rand(16) is Some(random) else { fail("random name unavailable") }
    let suffix = StringBuilder()
    for byte in random {
      suffix.write_string("-\{byte.to_int()}")
    }
    let temp = target + ".moonrdb" + suffix.to_string() + ".tmp"
    let file = @fs.open(temp[:], mode=WriteOnly, create_mode=CreateNew)
    let mut closed = false
    defer (if !closed { file.close() })
    errdefer {
      if !closed {
        file.close()
        closed = true
      }
      @fs.remove(temp[:]) catch {
        _ => ()
      }
    }
    let n = write_records(snapshot, db, encoded, line => file.text.write(line))
    file.sync()
    file.close()
    closed = true
    @fs.rename(temp[:], target[:], replace=true)
    n
  } else {
    write_records(snapshot, db, encoded, line => @stdio.stdout.text.write(line))
  }
  let checksum = match snapshot.checksum {
    Valid(_) => "valid"
    Disabled => "disabled"
  }
  @stdio.stderr.text.write(
    "moonrdb: export complete records=\{count} checksum=\{checksum}\n",
  )
}
