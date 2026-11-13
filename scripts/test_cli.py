"""Native CLI process checks: stdout, stderr, exit status and bounded file input."""

import argparse
import base64
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, required=True)
    parser.add_argument("--example", type=Path, required=True)
    args = parser.parse_args()
    exe = args.exe.resolve()
    example = args.example.resolve()
    root = Path(__file__).resolve().parents[1]
    checks = 0

    def run(arguments, code, *, stdout_contains=None, stderr_contains=None, cwd=root):
        nonlocal checks
        result = subprocess.run([str(exe), *map(str, arguments)], cwd=cwd,
                                capture_output=True, text=True, encoding="utf-8", timeout=20)
        if result.returncode != code:
            raise AssertionError(f"{arguments}: exit {result.returncode}, expected {code}: {result.stderr}")
        if code:
            if result.stdout:
                raise AssertionError("Failure emitted stdout or a completion marker")
            if not result.stderr or "status: complete" in result.stderr:
                raise AssertionError("Failure diagnostics missing or falsely complete")
        elif result.stderr:
            raise AssertionError(f"Success emitted stderr: {result.stderr}")
        if stdout_contains is not None and stdout_contains not in result.stdout:
            raise AssertionError(f"Missing stdout content {stdout_contains!r}: {result.stdout}")
        if stderr_contains is not None and stderr_contains not in result.stderr:
            raise AssertionError(f"Missing stderr content {stderr_contains!r}: {result.stderr}")
        checks += 1
        return result.stdout

    for folder, name, keys in [
        ("redis-7.2.5", "empty", 0),
        ("redis-7.2.5-no-checksum", "empty", 0),
        ("redis-7.2.5-strings", "strings", 15),
        ("redis-7.2.5-hashes", "hashes", 9),
        ("redis-7.2.5-lists", "lists", 8),
        ("redis-7.2.5-sets", "sets", 13),
        ("redis-7.2.5-sorted-sets", "sorted-sets", 8),
    ]:
        output = run(["inspect", root / "fixtures" / folder / (name + ".rdb")], 0,
                     stdout_contains="status: complete\n")
        expected = "checksum: disabled (CRC64 not validated)" if "no-checksum" in folder else "checksum: valid (CRC64)"
        if expected not in output or f"keys: {keys}\n" not in output:
            raise AssertionError("Fixture checksum/key report mismatch")

    for folder, name in [("redis-7.2.5", "empty"), ("redis-7.2.5-strings", "strings"),
                         ("redis-7.2.5-hashes", "hashes"), ("redis-7.2.5-lists", "lists"),
                         ("redis-7.2.5-sets", "sets"), ("redis-7.2.5-sorted-sets", "sorted-sets")]:
        path = root / "fixtures" / folder / (name + ".rdb")
        output = run(["top", path, "--limit", "10000"], 0, stdout_contains="status: complete")
        rows = [dict(item.split("=", 1) for item in line.split()) for line in output.splitlines() if line.startswith("rank=")]
        expected = sorted(rows, key=lambda row: (-int(row["serialized_bytes"]), int(row["db"]),
                                                base64.b64decode(row["key_base64"]), int(row["record_start"])))
        if rows != expected:
            raise AssertionError("TopN ranking differs from Python full sort")
        small = run(["top", path, "--by", "serialized-bytes", "--limit", "2"], 0)
        small_rows = [line for line in small.splitlines() if line.startswith("rank=")]
        all_rows = [line for line in output.splitlines() if line.startswith("rank=")]
        if small_rows != all_rows[:2]:
            raise AssertionError("TopN subset mismatch")
    for bad in [["--limit", "0"], ["--limit", "10001"], ["--limit", "-1"],
                ["--limit", "1_0"], ["--limit"], ["--by", "ram"],
                ["--limit", "1", "--limit", "2"], ["--prefix", "a"]]:
        run(["top", "f", *bad], 2, stderr_contains="invalid arguments")
    run(["top", "--help"], 0, stdout_contains="moonrdb top")

    stream_file = root / "fixtures/redis-7.2.5-streams/streams.rdb"
    report = run(["inspect", stream_file], 0, stdout_contains="function_libraries: 1")
    assert "keys: 3" in report and "checksum: valid" in report
    run(["stats", stream_file], 0, stdout_contains="db 0 type Stream: keys=2")
    run(["top", stream_file], 0, stdout_contains="type=Stream encoding=Listpacks3 entries=3")
    run(["diff", stream_file, stream_file], 0, stdout_contains="returned: 0")

    stats_file = root / "fixtures/redis-7.2.5-sorted-sets/sorted-sets.rdb"
    baseline = run(["stats", stats_file], 0, stdout_contains="expiry_evaluation: not_requested")
    for at, expected in [("2100-01-01T00:00:00.122Z", "ttl_le_1h: 1"),
                         ("2100-01-01T00:00:00.123Z", "expired: 1"),
                         ("2100-01-01T00:00:00.124Z", "expired: 1")]:
        out = run(["stats", stats_file, "--at", at, "--prefix", "long-", "--prefix", ""], 0,
                  stdout_contains=expected)
        if "accounting_matches: true" not in out or "keys=1 serialized_bytes=" not in out:
            raise AssertionError("Stats prefix or accounting mismatch")
    for bad in [["--at", "2026-02-29T00:00:00Z"], ["--at", "0"],
                ["--prefix"], ["--prefix", "a", "--prefix", "a"],
                ["--at", "1970-01-01T00:00:00Z", "--at", "1970-01-01T00:00:00Z"]]:
        run(["stats", stats_file, *bad], 2, stderr_contains="invalid arguments")
    run(["stats", "--help"], 0, stdout_contains="stats options:")
    if run(["stats", stats_file], 0) != baseline:
        raise AssertionError("Default stats changed after reference-time invocation")

    for arguments in [["--help"], ["-h"], ["inspect", "--help"]]:
        run(arguments, 0, stdout_contains="Usage: moonrdb inspect")
    for arguments in [[], ["inspect"], ["unknown", "x"], ["inspect", "a", "b"],
                      ["inspect", "a", "--at", "0"], ["inspect", "--max-input-bytes"],
                      ["inspect", "a", "--max-input-bytes", "2147483648"],
                      ["inspect", "a", "--max-input-bytes", "0"],
                      ["inspect", "a", "--max-input-bytes", "1_000"],
                      ["inspect", "a", "--max-input-bytes", "1", "--max-input-bytes", "2"]]:
        run(arguments, 2, stderr_contains="invalid arguments")

    with tempfile.TemporaryDirectory(prefix="moonrdb-cli-") as temp:
        work = Path(temp)
        valid = (root / "fixtures/redis-7.2.5/empty.rdb").read_bytes()
        def diff_fixture(name, body):
            (work / name).write_bytes(b"REDIS0011" + body + b"\xff" + bytes(8))

        diff_fixture("before.rdb", b"\x00\x01a\x01v\x00\x01b\x01v\x00\x01c\x01v")
        diff_fixture("after.rdb", b"\x00\x01a\x02vv\x02\x01b\x01\x01v\x00\x01d\x01v")
        args = ["diff", "before.rdb", "after.rdb"]
        report = run(args, 0, cwd=work)
        assert "added: 1\nremoved: 1\ntype_changed: 1\nsize_changed: 2" in report
        assert "key_base64=Yg== before_type=String after_type=Set" in report
        assert report == run(args, 0, cwd=work)
        assert "returned: 1" in run([*args, "--limit", "1"], 0, cwd=work)
        assert "returned: 0" in run([*args, "--db", "2"], 0, cwd=work)
        assert "delta_bytes=1" in run([*args, "--prefix", "a"], 0, cwd=work)
        assert "returned: 0" in run(["diff", "before.rdb", "before.rdb"], 0, cwd=work)
        run(["diff", "before.rdb"], 2, cwd=work)
        run([*args, "--limit", "0"], 2, cwd=work)
        diff_fixture("duplicate.rdb", b"\x00\x01a\x01v\x00\x01a\x01v")
        run(["diff", "before.rdb", "duplicate.rdb"], 1, cwd=work)
        (work / "broken.rdb").write_bytes(b"REDIS0011")
        run(["diff", "before.rdb", "broken.rdb"], 1, cwd=work)

        diff_fixture("semantic-before.rdb",
                     b"\x00\x01a\x01x\xfc" + (100).to_bytes(8, "little") +
                     b"\x00\x01b\x01x\x02\x01s\x02\x01a\x01b")
        diff_fixture("semantic-after.rdb",
                     b"\x00\x01a\x01y\xfc" + (200).to_bytes(8, "little") +
                     b"\x00\x01b\x01x\x02\x01s\x02\x01b\x01a")
        report = run(["diff", "semantic-before.rdb", "semantic-after.rdb"], 0, cwd=work)
        assert "size_changed: 0\ncontent_changed: 1\nexpiry_changed: 1\nreturned: 2" in report
        assert "delta_bytes=0 content_changed=true expiry_changed=false" in report
        assert "delta_bytes=0 content_changed=false expiry_changed=true" in report

        assert "before_expiry_ms=100 after_expiry_ms=200" in report
        report = run(["diff", "before.rdb", "semantic-before.rdb"], 0, cwd=work)
        assert "before_expiry_ms=persistent after_expiry_ms=100" in report
        report = run(["diff", "semantic-before.rdb", "before.rdb"], 0, cwd=work)
        assert "before_expiry_ms=100 after_expiry_ms=persistent" in report

        cases = [
            ("empty.rdb", b"", "UnexpectedEnd"),
            ("truncated.rdb", valid[:-1], "UnexpectedEnd"),
            ("bad-magic.rdb", b"BADIS" + valid[5:], "InvalidMagic"),
            ("version.rdb", b"REDIS0012" + valid[9:], "UnsupportedVersion"),
            ("unsupported.rdb", b"REDIS0011\x07", "UnsupportedObjectType"),
            ("unknown-op.rdb", b"REDIS0011\xf6", "UnsupportedOpcode"),
            ("checksum.rdb", valid[:-1] + bytes([valid[-1] ^ 1]), "ChecksumMismatch"),
            ("trailing.rdb", valid + b"x", "TrailingData"),
        ]
        for name, data, message in cases:
            (work / name).write_bytes(data)
            run(["inspect", name], 1, stderr_contains=message, cwd=work)
            run(["top", name], 1, stderr_contains=message, cwd=work)
            run(["stats", name, "--at", "1970-01-01T00:00:00Z"], 1, stderr_contains=message, cwd=work)
        # Actual Unicode and spaces in a native argv path, plus end-of-options.
        for name in ["快照 with spaces.rdb", "-snapshot.rdb"]:
            (work / name).write_bytes(valid)
            options = ["inspect", "--", name] if name.startswith("-") else ["inspect", name]
            run(options, 0, stdout_contains="status: complete", cwd=work)
        run(["inspect", "missing.rdb"], 1, stderr_contains="unable to read", cwd=work)
        run(["inspect", work], 1, stderr_contains="regular file")
        (work / "valid.rdb").write_bytes(valid)
        run(["inspect", "valid.rdb", "--max-input-bytes", str(len(valid))], 0,
            stdout_contains="status: complete", cwd=work)
        run(["inspect", "valid.rdb", "--max-input-bytes", str(len(valid) - 1)], 1,
            stderr_contains="input exceeds byte limit", cwd=work)
        with (work / "oversize.rdb").open("wb") as stream:
            stream.truncate(67108865)
        run(["inspect", "oversize.rdb"], 1, stderr_contains="input exceeds byte limit", cwd=work)
        # Reachable checksum-disabled file proves no terminal escape/key dumping.
        (work / "binary.rdb").write_bytes(b"REDIS0011\x00\x03\x1b\x00\xff\x01v\xff" + bytes(8))
        output = run(["inspect", "binary.rdb"], 0, stdout_contains="keys: 1", cwd=work)
        if "\x1b" in output or "\ufffd" in output:
            raise AssertionError("Binary key leaked into terminal output")
        example_result = subprocess.run([str(example)], cwd=work, capture_output=True,
                                        text=True, encoding="utf-8", timeout=20)
        if example_result.returncode != 0 or example_result.stderr or example_result.stdout != "db=0, value_matches=true\nchecksum_disabled=true\n":
            raise AssertionError("Standalone library example failed")
        checks += 1
    print(f"Native CLI: {checks} process checks passed (including library example).")


if __name__ == "__main__":
    main()
