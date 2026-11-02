"""Sorted Set fixtures: both save encodings, IEEE scores and binary members."""
import base64


def cases():
    return [
        (0, b"compact", [(b"", "-inf"), (b"\x00\xff", "-1.25"), (b"42", "0"), (b"tail", "inf")], None, "listpack"),
        (0, b"ties", [(b"a", "1"), (b"b", "1"), (b"c", "1")], None, "listpack"),
        (0, b"overflow", [(b"v0", "-inf"), (b"v1", "-1.25"), (b"v2", "0"), (b"v3", "1.7976931348623157e308"), (b"v4", "inf")], None, "skiplist"),
        (2, b"long-member", [(b"L" * 1000, "5e-324"), (b"other", "-0")], 4102444800123, "skiplist"),
        (2, b"packed-lzf", [(bytes([97+i]) * 60, str(i)) for i in range(4)], None, "listpack"),
        (2, b"zset:" + b"K" * 1024, [(b"value", "0.1"), (b"42", "-2e100")], None, "listpack"),
    ]


def verify(command, port, password):
    for db, key, pairs, expiry, encoding in cases():
        if command(port, password, "ZCARD", key, database=db) != len(pairs):
            raise RuntimeError("Sorted Set cardinality mismatch")
        for element, score in pairs:
            actual = command(port, password, "ZSCORE", key, element, database=db)
            if actual is None or float(actual) != float(score):
                raise RuntimeError("Sorted Set score mismatch")
        if command(port, password, "OBJECT", "ENCODING", key, database=db) != encoding:
            raise RuntimeError("Sorted Set encoding threshold mismatch")
        if command(port, password, "PEXPIRETIME", key, database=db) != (-1 if expiry is None else expiry):
            raise RuntimeError("Sorted Set expiry mismatch")
    if command(port, password, "GET", b"marker") != "mixed":
        raise RuntimeError("String marker mismatch")
    if command(port, password, "SISMEMBER", b"set-marker", b"value") != 1 or command(port, password, "SCARD", b"set-marker") != 1:
        raise RuntimeError("Set marker mismatch")
    for key in [b"marker", b"set-marker"]:
        if command(port, password, "PEXPIRETIME", key) != -1:
            raise RuntimeError("Marker expiry mismatch")


def populate(command, port, password):
    for db, key, pairs, expiry, _ in cases():
        for element, score in pairs:
            if command(port, password, "ZADD", key, score, element, database=db) != 1:
                raise RuntimeError("ZADD failed")
        if expiry is not None and command(port, password, "PEXPIREAT", key, expiry, database=db) != 1:
            raise RuntimeError("PEXPIREAT failed")
    if command(port, password, "SET", b"marker", b"mixed") != "OK" or command(port, password, "SADD", b"set-marker", b"value") != 1:
        raise RuntimeError("Marker setup failed")
    verify(command, port, password)
    def b64(value):
        return base64.b64encode(value).decode()
    return [{"type": "sorted-set", "database": db, "key_base64": b64(key),
             "entries": [{"element_base64": b64(element), "score": score} for element, score in pairs],
             "expires_at_ms": expiry, "expected_storage": encoding}
            for db, key, pairs, expiry, encoding in cases()] + [
        {"type": "string", "database": 0, "key_base64": b64(b"marker"), "value_base64": b64(b"mixed"), "expires_at_ms": None},
        {"type": "set", "database": 0, "key_base64": b64(b"set-marker"), "members_base64": [b64(b"value")], "expires_at_ms": None},
    ]
