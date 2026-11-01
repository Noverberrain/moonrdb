"""Small quicklist2 fixtures; the official DEBUG threshold avoids 1 GiB elements."""

import base64


def cases():
    return [
        (0, b"single", [b"\x00\xff", b""], None),
        (0, b"ordered", [b"first", b"-128", b"first", b"\x80\x00", b"0", b"9223372036854775807", b"last"], None),
        (0, b"compressed", [bytes([97 + i % 4]) * 60 for i in range(20)], None),
        (0, b"mixed", [b"head0", b"head1", b"\x00\xff" + b"p" * 126, b"tail0", b"tail1", b"tail2"], None),
        (0, b"list:" + b"K" * 1024, [b"v0", b"v1", b"v2"], None),
        (2, b"expiring", [b"a", b"b", b"c"], 4102444800123),
    ]


def verify(command, port, password):
    for db, key, items, expiry in cases():
        if command(port, password, "LLEN", key, database=db) != len(items):
            raise RuntimeError("List length mismatch")
        for index, value in enumerate(items):
            if command(port, password, "LINDEX", key, index, database=db, binary=True) != value:
                raise RuntimeError("List order/value mismatch")
        if command(port, password, "PEXPIRETIME", key, database=db) != (-1 if expiry is None else expiry):
            raise RuntimeError("List expiry mismatch")
    if command(port, password, "GET", b"marker", binary=True) != b"mixed":
        raise RuntimeError("String marker mismatch")
    if command(port, password, "HLEN", b"hash-marker") != 1 or command(port, password, "HGET", b"hash-marker", b"f", binary=True) != b"v":
        raise RuntimeError("Hash marker mismatch")
    for key in [b"marker", b"hash-marker"]:
        if command(port, password, "PEXPIRETIME", key) != -1:
            raise RuntimeError("Marker expiry mismatch")


def populate(command, port, password):
    if command(port, password, "DEBUG", "QUICKLIST-PACKED-THRESHOLD", 64) != "OK":
        raise RuntimeError("Cannot lower test-only plain-node threshold")
    for db, key, items, expiry in cases():
        for index, value in enumerate(items):
            if command(port, password, "RPUSH", key, value, database=db) != index + 1:
                raise RuntimeError("RPUSH failed")
        if expiry is not None and command(port, password, "PEXPIREAT", key, expiry, database=db) != 1:
            raise RuntimeError("PEXPIREAT failed")
    if command(port, password, "SET", b"marker", b"mixed") != "OK" or command(port, password, "HSET", b"hash-marker", b"f", b"v") != 1:
        raise RuntimeError("Marker setup failed")
    verify(command, port, password)
    def b64(value):
        return base64.b64encode(value).decode()
    expected = [{"type": "list", "database": db, "key_base64": b64(key),
                 "items_base64": [b64(value) for value in items], "expires_at_ms": expiry}
                for db, key, items, expiry in cases()]
    return expected + [
        {"type": "string", "database": 0, "key_base64": b64(b"marker"), "value_base64": b64(b"mixed"), "expires_at_ms": None},
        {"type": "hash", "database": 0, "key_base64": b64(b"hash-marker"), "fields": [{"field_base64": b64(b"f"), "value_base64": b64(b"v")}], "expires_at_ms": None},
    ]
