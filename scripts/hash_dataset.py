"""Hash cases straddle fixed listpack thresholds; verification ignores field order."""

import base64


def cases():
    return [
        (0, b"compact", [(b"name", b"alice"), (b"age", b"42"), (b"\x00\xff", b"\x80\x00"), (b"", b"")], None, "listpack"),
        (0, b"count-overflow", [(f"f{i}".encode(), f"v{i}".encode()) for i in range(5)], None, "hashtable"),
        (0, b"long-value", [(b"payload", b"x" * 1000)], None, "hashtable"),
        (0, b"long-field", [(b"f" * 65, b"v")], None, "hashtable"),
        (0, b"key:" + b"K" * 1024, [(b"f", b"v")], None, "listpack"),
        (2, b"ints", [(b"-4096", b"4095"), (b"-32768", b"32767"), (b"-8388608", b"8388607"), (b"-9223372036854775808", b"9223372036854775807")], 4102444800123, "listpack"),
        (2, b"ints2", [(b"-2147483648", b"2147483647"), (b"127", b"128")], None, "listpack"),
        (2, b"packed-lzf", [(f"f{i}".encode(), bytes([97 + i]) * 60) for i in range(4)], None, "listpack"),
    ]


def verify(command, port, password):
    if command(port, password, "GET", b"marker", binary=True) != b"mixed":
        raise RuntimeError("Mixed String mismatch")
    if command(port, password, "PEXPIRETIME", b"marker") != -1:
        raise RuntimeError("Mixed String expiry mismatch")
    for db, key, pairs, expiry, storage in cases():
        if command(port, password, "HLEN", key, database=db) != len(pairs):
            raise RuntimeError("Hash length mismatch")
        if command(port, password, "OBJECT", "ENCODING", key, database=db) != storage:
            raise RuntimeError("Hash runtime threshold expectation failed")
        for field, value in pairs:
            if command(port, password, "HGET", key, field, database=db, binary=True) != value:
                raise RuntimeError("Hash field mismatch")
        if command(port, password, "PEXPIRETIME", key, database=db) != (-1 if expiry is None else expiry):
            raise RuntimeError("Hash expiry mismatch")


def populate(command, port, password):
    for db, key, pairs, expiry, _ in cases():
        for field, value in pairs:
            if command(port, password, "HSET", key, field, value, database=db) != 1:
                raise RuntimeError("HSET failed")
        if expiry is not None:
            if command(port, password, "PEXPIREAT", key, expiry, database=db) != 1:
                raise RuntimeError("PEXPIREAT failed")
    if command(port, password, "SET", b"marker", b"mixed") != "OK":
        raise RuntimeError("SET failed")
    verify(command, port, password)
    def b64(value):
        return base64.b64encode(value).decode()
    expected = [{"type": "hash", "database": db, "key_base64": b64(key),
                 "fields": [{"field_base64": b64(field), "value_base64": b64(value)} for field, value in pairs],
                 "expires_at_ms": expiry, "expected_storage": storage}
                for db, key, pairs, expiry, storage in cases()]
    return expected + [{"type": "string", "database": 0, "key_base64": b64(b"marker"), "value_base64": b64(b"mixed"), "expires_at_ms": None}]
