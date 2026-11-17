// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn binary_json(bytes : Bytes) -> Json {
  { "encoding": "base64", "data": @base64.encode(bytes[:]) }
}

///|
fn nullable_time(value : Int64?) -> Json {
  match value {
    Some(v) => Json::string(v.to_string())
    None => Json::null()
  }
}

///|
fn record_json(record : @moonrdb.RdbRecord) -> Json {
  let (db, key, size, start, kind, storage, _, _) = top_meta(record)
  let (expiry, idle, freq, end, key_storage) = match record {
    String(r) =>
      (
        r.expires_at_ms,
        r.idle_seconds,
        r.frequency,
        r.record_end,
        r.key_storage,
      )
    Hash(r) =>
      (
        r.expires_at_ms,
        r.idle_seconds,
        r.frequency,
        r.record_end,
        r.key_storage,
      )
    List(r) =>
      (
        r.expires_at_ms,
        r.idle_seconds,
        r.frequency,
        r.record_end,
        r.key_storage,
      )
    Set(r) =>
      (
        r.expires_at_ms,
        r.idle_seconds,
        r.frequency,
        r.record_end,
        r.key_storage,
      )
    Stream(r) =>
      (
        r.expires_at_ms,
        r.idle_seconds,
        r.frequency,
        r.record_end,
        r.key_storage,
      )
    SortedSet(r) =>
      (
        r.expires_at_ms,
        r.idle_seconds,
        r.frequency,
        r.record_end,
        r.key_storage,
      )
  }
  let fields : Map[String, Json] = {
    "schema": "moonrdb.record.v1",
    "database": Json::string(db.to_string()),
    "key": binary_json(key),
    "type": Json::string(kind),
    "storage": Json::string(storage),
    "key_storage": Json::string(repr(key_storage)),
    "serialized_bytes": Json::string(size.to_string()),
    "record_start": Json::string(start.to_string()),
    "record_end": Json::string(end.to_string()),
    "expires_at_ms": nullable_time(expiry),
    "idle_seconds": match idle {
      Some(v) => Json::string(v.to_string())
      None => Json::null()
    },
    "frequency": match freq {
      Some(v) => Json::string(v.to_int().to_string())
      None => Json::null()
    },
  }
  match record {
    String(r) => fields["value"] = binary_json(r.value)
    Hash(r) => {
      fields["entries"] = Json::array(
        r.entries.map(e => {
          "field": binary_json(e.field),
          "value": binary_json(e.value),
        }),
      )
      fields["packed_storage"] = match r.packed_storage {
        Some(v) => Json::string(repr(v))
        None => Json::null()
      }
    }
    List(r) => {
      fields["items"] = Json::array(r.items.map(binary_json))
      fields["nodes"] = Json::array(
        r.nodes.map(n => {
          "container": Json::string(repr(n.container)),
          "storage": Json::string(repr(n.storage)),
          "item_start": Json::string(n.item_start.to_string()),
          "item_end": Json::string(n.item_end.to_string()),
          "node_start": Json::string(n.node_start.to_string()),
          "node_end": Json::string(n.node_end.to_string()),
        }),
      )
    }
    Set(r) => {
      fields["members"] = Json::array(r.members.map(binary_json))
      fields["packed_storage"] = match r.packed_storage {
        Some(v) => Json::string(repr(v))
        None => Json::null()
      }
    }
    Stream(r) => {
      fields["length"] = Json::string(r.length.to_string())
      fields["group_count"] = Json::string(r.group_count.to_string())
      fields["groups"] = Json::array(r.groups.map(stream_group_json))
      fields["entries"] = Json::array(
        r.entries.map(e => {
          "milliseconds": Json::string(e.milliseconds.to_string()),
          "sequence": Json::string(e.sequence.to_string()),
          "fields": Json::array(
            e.fields.map(pair => {
              "field": binary_json(pair.field),
              "value": binary_json(pair.value),
            }),
          ),
        }),
      )
      fields["rdb_payload"] = binary_json(r.payload)
    }
    SortedSet(r) => {
      fields["entries"] = Json::array(
        r.entries.map(e => {
          "element": binary_json(e.element),
          "score": Json::string(e.score.to_string()),
          "score_bits_u64": Json::string(
            e.score.reinterpret_as_uint64().to_string(),
          ),
        }),
      )
      fields["packed_storage"] = match r.packed_storage {
        Some(v) => Json::string(repr(v))
        None => Json::null()
      }
    }
  }
  Json::object(fields)
}

///|
fn stream_id_json(id : @moonrdb.StreamMessageId) -> Json {
  {
    "milliseconds": Json::string(id.milliseconds.to_string()),
    "sequence": Json::string(id.sequence.to_string()),
  }
}

///|
fn stream_group_json(group : @moonrdb.StreamGroup) -> Json {
  {
    "name": binary_json(group.name),
    "last_delivered_id": stream_id_json(group.last_delivered_id),
    "entries_read": if group.entries_read == -1L {
      Json::null()
    } else {
      Json::string(group.entries_read.to_string())
    },
    "pending_count": Json::string(group.pending_count.to_string()),
    "consumers": Json::array(
      group.consumers.map(consumer => {
        "name": binary_json(consumer.name),
        "seen_time_ms": Json::string(consumer.seen_time_ms.to_string()),
        "active_time_ms": Json::string(consumer.active_time_ms.to_string()),
        "pending_count": Json::string(consumer.pending.length().to_string()),
        "pending": Json::array(
          consumer.pending.map(message => {
            "id": stream_id_json(message.id),
            "delivery_time_ms": Json::string(
              message.delivery_time_ms.to_string(),
            ),
            "delivery_count": Json::string(message.delivery_count.to_string()),
          }),
        ),
      }),
    ),
  }
}
