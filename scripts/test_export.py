"""Export round trips and atomic-output process checks using only Python stdlib."""
import argparse
import base64
import json
from pathlib import Path
import struct
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, required=True)
    exe = parser.parse_args().exe.resolve()
    root = Path(__file__).resolve().parents[1]
    checks = 0

    def run(arguments, code=0, cwd=root):
        nonlocal checks
        p = subprocess.run([str(exe), "export", *map(str, arguments)], cwd=cwd,
                           capture_output=True, text=True, encoding="utf-8", timeout=20)
        assert p.returncode == code, (arguments, p.returncode, p.stderr)
        if code:
            assert not p.stdout and "export complete" not in p.stderr, p
        else:
            assert "export complete records=" in p.stderr, p.stderr
        checks += 1
        return p

    def binary(value):
        assert value["encoding"] == "base64"
        return base64.b64decode(value["data"], validate=True)

    def b64(value):
        return base64.b64decode(value)

    for folder in sorted((root / "fixtures").glob("redis-7.2.5*")):
        manifest = json.loads((folder / "manifest.json").read_text())
        path = folder / manifest["file"]
        expected_file = folder / "expected.json"
        expected = json.loads(expected_file.read_text()) if expected_file.exists() else []
        output = run([path]).stdout
        rows = [json.loads(line) for line in output.splitlines()]
        assert len(rows) == len(expected)
        by_key = {(int(r["database"]), binary(r["key"])): r for r in rows}
        for e in expected:
            e.setdefault("type", "string")
            r = by_key[(e["database"], b64(e["key_base64"]))]
            assert r["schema"] == "moonrdb.record.v1"
            assert r["type"].lower().replace("sortedset", "sorted-set") == e["type"]
            assert r["expires_at_ms"] == (None if e["expires_at_ms"] is None else str(e["expires_at_ms"]))
            for field in ["database", "serialized_bytes", "record_start", "record_end"]:
                assert isinstance(r[field], str)
            assert int(r["record_end"]) - int(r["record_start"]) == int(r["serialized_bytes"])
            if e["type"] == "string":
                assert binary(r["value"]) == b64(e["value_base64"])
            elif e["type"] == "hash":
                assert {binary(x["field"]): binary(x["value"]) for x in r["entries"]} == {b64(x["field_base64"]): b64(x["value_base64"]) for x in e["fields"]}
            elif e["type"] == "list":
                assert list(map(binary, r["items"])) == list(map(b64, e["items_base64"]))
            elif e["type"] == "set":
                assert set(map(binary, r["members"])) == set(map(b64, e["members_base64"]))
            else:
                actual = {binary(x["element"]): struct.unpack("<d", struct.pack("<Q", int(x["score_bits_u64"])))[0] for x in r["entries"]}
                assert actual == {b64(x["element_base64"]): float(x["score"]) for x in e["entries"]}
        filtered = run([path, "--db", "2", "--prefix", ""]).stdout
        assert [json.loads(x) for x in filtered.splitlines()] == [r for r in rows if r["database"] == "2"]
        assert not run([path, "--prefix", "no-such-prefix"]).stdout

    with tempfile.TemporaryDirectory(prefix="moonrdb-export-") as temp:
        work = Path(temp)
        source = root / "fixtures/redis-7.2.5-sorted-sets/sorted-sets.rdb"
        target = work / "导出 with spaces.jsonl"
        target.write_bytes(b"old output")
        expected = run([source]).stdout
        p = run([source, "--format", "jsonl", "--output", target])
        assert not p.stdout and target.read_text(encoding="utf-8") == expected
        assert not list(work.glob("*.tmp"))
        run([source, "--prefix", "missing", "--output", target])
        assert target.read_bytes() == b""
        for data in [b"", b"REDIS0012", source.read_bytes()[:-1], b"REDIS0011\x15", source.read_bytes() + b"x"]:
            bad = work / "bad.rdb"
            bad.write_bytes(data)
            target.write_bytes(b"keep")
            run([bad, "--output", target], 1)
            assert target.read_bytes() == b"keep" and not list(work.glob("*.tmp"))
        copy = work / "input.rdb"
        copy.write_bytes(source.read_bytes())
        original = copy.read_bytes()
        run([copy, "--output", copy], 1)
        assert copy.read_bytes() == original
        directory = work / "destination"
        directory.mkdir()
        (directory / "keep").write_bytes(b"unchanged")
        run([source, "--output", directory], 1)
        assert (directory / "keep").read_bytes() == b"unchanged"
        assert not list(work.glob("*.tmp"))
        run([source, "--output", work / "missing" / "out.jsonl"], 1)
        for args in [["--db", "-1"], ["--db", "18446744073709551616"], ["--format", "csv"], ["--output", "-"], ["--prefix", "a", "--prefix", "b"]]:
            run([source, *args], 2)
        # Preserve values outside JavaScript's exact integer range and IEEE negative zero.
        body = b"\xfe\x81" + bytes([255])*8 + b"\xfc" + struct.pack("<q", -9223372036854775808) + b"\x05\x00\x01\x00" + struct.pack("<d", -0.0)
        copy.write_bytes(b"REDIS0011" + body + b"\xff" + bytes(8))
        row = json.loads(run([copy, "--db", "18446744073709551615"]).stdout)
        assert row["database"] == "18446744073709551615" and row["expires_at_ms"] == "-9223372036854775808"
        assert row["entries"][0]["score_bits_u64"] == "9223372036854775808"
        copy.write_bytes(b"REDIS0011\x00\x08" + "用户:1".encode() + b"\x01v\xff" + bytes(8))
        assert binary(json.loads(run([copy, "--prefix", "用户:"]).stdout)["key"]) == "用户:1".encode()
    print(f"JSONL export: {checks} process checks passed; all fixture records round-tripped.")


if __name__ == "__main__":
    main()
