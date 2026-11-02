"""Native CLI process checks: stdout, stderr, exit status and bounded file input."""

import argparse
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
    for arguments in [[], ["inspect"], ["export", "x"], ["inspect", "a", "b"],
                      ["inspect", "a", "--at", "0"], ["inspect", "--max-input-bytes"],
                      ["inspect", "a", "--max-input-bytes", "2147483648"],
                      ["inspect", "a", "--max-input-bytes", "0"],
                      ["inspect", "a", "--max-input-bytes", "1_000"],
                      ["inspect", "a", "--max-input-bytes", "1", "--max-input-bytes", "2"]]:
        run(arguments, 2, stderr_contains="invalid arguments")

    with tempfile.TemporaryDirectory(prefix="moonrdb-cli-") as temp:
        work = Path(temp)
        valid = (root / "fixtures/redis-7.2.5/empty.rdb").read_bytes()
        cases = [
            ("empty.rdb", b"", "UnexpectedEnd"),
            ("truncated.rdb", valid[:-1], "UnexpectedEnd"),
            ("bad-magic.rdb", b"BADIS" + valid[5:], "InvalidMagic"),
            ("version.rdb", b"REDIS0012" + valid[9:], "UnsupportedVersion"),
            ("unsupported.rdb", b"REDIS0011\x15", "UnsupportedObjectType"),
            ("unknown-op.rdb", b"REDIS0011\xf5", "UnsupportedOpcode"),
            ("checksum.rdb", valid[:-1] + bytes([valid[-1] ^ 1]), "ChecksumMismatch"),
            ("trailing.rdb", valid + b"x", "TrailingData"),
        ]
        for name, data, message in cases:
            (work / name).write_bytes(data)
            run(["inspect", name], 1, stderr_contains=message, cwd=work)
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
