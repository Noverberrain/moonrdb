"""Synthetic String dataset, checked against Redis before SAVE and after reload."""

import base64


def cases():
    return [
        (0, b"plain", b"hello world!", None),
        (0, b"", b"", None),
        (0, b"\x00\xffkey", b"\x00\xff\x80value\x00", None),
        (0, b"int8", b"-128", None),
        (0, b"int16", b"-32768", None),
        (0, b"int32", b"-2147483648", None),
        (0, b"leading-zero", b"00123", None),
        (0, b"wide-int", b"9007199254740993", None),
        (0, b"lzf", b"abc" * 2048, None),
        (0, b"key:" + b"K" * 1024, b"compressed-key-value", None),
        (0, b"expiring", b"alive", 4102444800123),
        (2, b"plain", b"db two", None),
        (2, b"int8-max", b"127", None),
        (2, b"int16-max", b"32767", None),
        (2, b"int32-max", b"2147483647", None),
    ]


def verify(command, port, password):
    for db, key, value, expiry in cases():
        if command(port, password, "GET", key, database=db, binary=True) != value:
            raise RuntimeError(f"Redis GET mismatch in DB {db}: {key!r}")
        actual = command(port, password, "PEXPIRETIME", key, database=db)
        if actual != (-1 if expiry is None else expiry):
            raise RuntimeError(f"Redis expiry mismatch in DB {db}: {key!r}")


def populate(command, port, password):
    for db, key, value, expiry in cases():
        if command(port, password, "SET", key, value, database=db) != "OK":
            raise RuntimeError("SET failed")
        if expiry is not None:
            if command(port, password, "PEXPIREAT", key, expiry, database=db) != 1:
                raise RuntimeError("PEXPIREAT failed")
    verify(command, port, password)
    return [{
        "database": db,
        "key_base64": base64.b64encode(key).decode(),
        "value_base64": base64.b64encode(value).decode(),
        "expires_at_ms": expiry,
    } for db, key, value, expiry in cases()]
