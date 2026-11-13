"""Redis 7.2.5 Stream and FUNCTION2 fixture."""
import base64

LIBRARY = "#!lua name=moonrdb_fixture\nredis.register_function('hello', function() return 42 end)"


def populate(command, port, password):
    def call(*args, **kwargs):
        return command(port, password, *args, **kwargs)

    call("CONFIG", "SET", "stream-node-max-entries", 3)
    call("XADD", "stream", "100-0", "f", b"\x00\xff", "f", "duplicate")
    call("XADD", "stream", "100-1", "f", "second", "f", "value")
    call("XADD", "stream", "101-0", "other", "deleted")
    call("XADD", "stream", "102-0", "other", "tail")
    call("XGROUP", "CREATE", "stream", "group", "0")
    call("XREADGROUP", "GROUP", "group", "alice", "COUNT", "3", "STREAMS", "stream", ">", binary=True)
    call("XDEL", "stream", "101-0")
    call("XGROUP", "CREATECONSUMER", "stream", "group", "bob")
    call("XGROUP", "CREATE", "empty-stream", "empty-group", "$", "MKSTREAM")
    call("FUNCTION", "LOAD", LIBRARY)
    call("SET", "following", "still readable", database=2)
    return [
        {"database": 0, "key_base64": b64(b"stream"), "type": "stream", "expires_at_ms": None,
         "length": 3, "groups": 1,
         "entries": [["100-0", [b64(b"f"), b64(b"\x00\xff"), b64(b"f"), b64(b"duplicate")]],
                     ["100-1", [b64(b"f"), b64(b"second"), b64(b"f"), b64(b"value")]],
                     ["102-0", [b64(b"other"), b64(b"tail")]]]},
        {"database": 0, "key_base64": b64(b"empty-stream"), "type": "stream", "expires_at_ms": None,
         "length": 0, "groups": 1, "entries": []},
        {"database": 2, "key_base64": b64(b"following"), "type": "string", "expires_at_ms": None,
         "value_base64": b64(b"still readable")},
    ]


def b64(data):
    return base64.b64encode(data).decode("ascii")


def verify(command, port, password):
    def call(*args, **kwargs):
        return command(port, password, *args, **kwargs)

    assert call("XRANGE", "stream", "-", "+", binary=True) == [
        [b"100-0", [b"f", b"\x00\xff", b"f", b"duplicate"]],
        [b"100-1", [b"f", b"second", b"f", b"value"]],
        [b"102-0", [b"other", b"tail"]],
    ]
    assert call("XPENDING", "stream", "group", binary=True)[0] == 3
    assert len(call("XINFO", "CONSUMERS", "stream", "group")) == 2
    assert call("XLEN", "empty-stream") == 0
    assert call("FCALL", "hello", 0) == 42
    assert call("GET", "following", database=2) == "still readable"
