"""Redis Set fixtures covering all 7.2.5 save encodings and fixed thresholds."""

import base64


def cases():
    return [
        (0, b"int16", [b"-32768", b"-1", b"0", b"32767"], None, "intset"),
        (0, b"int32", [b"-2147483648", b"0", b"2147483647"], None, "intset"),
        (2, b"int64", [b"-9223372036854775808", b"0", b"9223372036854775807"], 4102444800123, "intset"),
        (0, b"compact", [b"alpha", b"", b"\x00\xff", b"00123"], None, "listpack"),
        (0, b"mixed-int", [b"alpha", b"42", b"-128", b"9223372036854775807"], None, "listpack"),
        (0, b"overflow", [f"v{i}".encode() for i in range(5)], None, "hashtable"),
        (0, b"ints-overflow", [str(i).encode() for i in range(5)], None, "hashtable"),
        (0, b"long-value", [b"x" * 1000, b"short"], None, "hashtable"),
        (2, b"packed-lzf", [bytes([97 + i]) * 60 for i in range(4)], None, "listpack"),
        (2, b"set:" + b"K" * 1024, [b"value", b"42"], None, "listpack"),
    ]


def verify(command, port, password):
    for db, key, values, expiry, storage in cases():
        if command(port, password, "SCARD", key, database=db) != len(values):
            raise RuntimeError("Set cardinality mismatch")
        for value in values:
            if command(port, password, "SISMEMBER", key, value, database=db) != 1:
                raise RuntimeError("Set membership mismatch")
        if command(port, password, "OBJECT", "ENCODING", key, database=db) != storage:
            raise RuntimeError("Set runtime threshold expectation failed")
        if command(port, password, "PEXPIRETIME", key, database=db) != (-1 if expiry is None else expiry):
            raise RuntimeError("Set expiry mismatch")
    if command(port, password, "GET", b"marker", binary=True) != b"mixed":
        raise RuntimeError("String marker mismatch")
    if command(port, password, "HLEN", b"hash-marker") != 1 or command(port, password, "HGET", b"hash-marker", b"f", binary=True) != b"v":
        raise RuntimeError("Hash marker mismatch")
    if command(port, password, "LLEN", b"list-marker") != 2:
        raise RuntimeError("List marker length mismatch")
    for i, value in enumerate([b"left", b"right"]):
        if command(port, password, "LINDEX", b"list-marker", i, binary=True) != value:
            raise RuntimeError("List marker order mismatch")
    for key in [b"marker", b"hash-marker", b"list-marker"]:
        if command(port, password, "PEXPIRETIME", key) != -1:
            raise RuntimeError("Marker expiry mismatch")


def populate(command, port, password):
    for db, key, values, expiry, _ in cases():
        for value in values:
            if command(port, password, "SADD", key, value, database=db) != 1:
                raise RuntimeError("SADD failed")
        if expiry is not None and command(port, password, "PEXPIREAT", key, expiry, database=db) != 1:
            raise RuntimeError("PEXPIREAT failed")
    if command(port, password, "SET", b"marker", b"mixed") != "OK" or command(port, password, "HSET", b"hash-marker", b"f", b"v") != 1:
        raise RuntimeError("Marker setup failed")
    for i, value in enumerate([b"left", b"right"]):
        if command(port, password, "RPUSH", b"list-marker", value) != i + 1:
            raise RuntimeError("List marker setup failed")
    verify(command, port, password)
    def b64(value):
        return base64.b64encode(value).decode()
    expected = [{"type": "set", "database": db, "key_base64": b64(key),
                 "members_base64": [b64(value) for value in values], "expires_at_ms": expiry, "expected_storage": storage}
                for db, key, values, expiry, storage in cases()]
    return expected + [
        {"type": "string", "database": 0, "key_base64": b64(b"marker"), "value_base64": b64(b"mixed"), "expires_at_ms": None},
        {"type": "hash", "database": 0, "key_base64": b64(b"hash-marker"), "fields": [{"field_base64": b64(b"f"), "value_base64": b64(b"v")}], "expires_at_ms": None},
        {"type": "list", "database": 0, "key_base64": b64(b"list-marker"), "items_base64": [b64(b"left"), b64(b"right")], "expires_at_ms": None},
    ]
