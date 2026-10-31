"""Generate an empty RDB using an isolated Redis 7.2.5 process, never an existing server."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import tempfile
import time


def command(port, password, *args):
    """Minimal RESP client for fixture generation, not part of the MoonBit parser."""
    with socket.create_connection(("127.0.0.1", port), timeout=2) as sock:
        stream = sock.makefile("rb")

        def request(parts):
            parts = [str(part).encode() for part in parts]
            sock.sendall(b"*%d\r\n" % len(parts) + b"".join(
                b"$%d\r\n" % len(part) + part + b"\r\n" for part in parts
            ))
            line = stream.readline()
            if line.startswith(b"-"):
                raise RuntimeError(line.decode().strip())
            if line.startswith(b"+"):
                return line[1:-2].decode()
            if line.startswith(b":"):
                return int(line[1:-2])
            if line.startswith(b"$"):
                length = int(line[1:-2])
                data = stream.read(length)
                if stream.read(2) != b"\r\n":
                    raise RuntimeError("Incomplete bulk reply")
                return data.decode()
            raise RuntimeError("Unexpected Redis reply")

        if request(["AUTH", password]) != "OK":
            raise RuntimeError("Authentication failed")
        return request(args)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--redis-bin", required=True, type=Path)
    parser.add_argument("--checksum", choices=["enabled", "disabled"], default="enabled")
    parser.add_argument("--output-dir", required=True, type=Path,
                        help="Must not exist; use .work/empty-regenerated for a new run")
    args = parser.parse_args()
    suffix = ".exe" if os.name == "nt" else ""
    server = (args.redis_bin / ("redis-server" + suffix)).resolve()
    checker = (args.redis_bin / ("redis-check-rdb" + suffix)).resolve()
    version = subprocess.check_output([str(server), "--version"], text=True).strip()
    if not version.startswith("Redis server v=7.2.5 "):
        raise RuntimeError(f"Expected Redis 7.2.5, got: {version}")
    if args.output_dir.exists():
        raise FileExistsError(f"Refusing to overwrite {args.output_dir}")
    # Bind a candidate port briefly. A unique password prevents touching an unrelated
    # server if another process wins the port between close() and Redis startup.
    with socket.socket() as candidate:
        candidate.bind(("127.0.0.1", 0))
        port = candidate.getsockname()[1]
    password = secrets.token_hex(32)
    with tempfile.TemporaryDirectory(prefix="moonrdb-empty-") as temp:
        work = Path(temp)
        config = work / "redis.conf"
        config.write_text(
            f'bind 127.0.0.1\nport {port}\nrequirepass {password}\n'
            'protected-mode yes\ndaemonize no\nsave ""\nappendonly no\n'
            f'databases 16\ndbfilename empty.rdb\nrdbchecksum {"yes" if args.checksum == "enabled" else "no"}\nrdbcompression yes\n',
            encoding="utf-8",
        )
        with (work / "server.log").open("wb") as log:
            proc = subprocess.Popen([str(server), config.name], cwd=work,
                                    stdout=log, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 15
                while True:
                    if proc.poll() is not None:
                        raise RuntimeError("Redis exited before becoming ready:\n" +
                                           (work / "server.log").read_text(errors="replace"))
                    try:
                        if command(port, password, "PING") == "PONG":
                            break
                    except (OSError, RuntimeError):
                        if time.monotonic() >= deadline:
                            raise TimeoutError("Redis startup timed out")
                        time.sleep(0.1)
                # No FLUSH commands and no connections to a user-provided endpoint.
                if command(port, password, "INFO", "keyspace").strip() != "# Keyspace":
                    raise RuntimeError("Fresh Redis instance is unexpectedly nonempty")
                if command(port, password, "SAVE") != "OK":
                    raise RuntimeError("SAVE failed")
                check = subprocess.check_output(
                    [str(checker), "empty.rdb"], text=True, cwd=work,
                    stderr=subprocess.STDOUT,
                )
                checksum_message = "Checksum OK" if args.checksum == "enabled" else "checksum disabled"
                if checksum_message not in check or "0 keys read" not in check:
                    raise RuntimeError(f"Unexpected redis-check-rdb output: {check}")
                data = (work / "empty.rdb").read_bytes()
                if data[:9] != b"REDIS0011" or data[-9] != 255:
                    raise RuntimeError("Unexpected RDB framing")
                args.output_dir.mkdir(parents=True)
                shutil.copyfile(work / "empty.rdb", args.output_dir / "empty.rdb")
                (args.output_dir / "redis-check-rdb.txt").write_text(check, encoding="utf-8")
                manifest = {
                    "redis_version": "7.2.5",
                    "upstream_commit": "f60370ce28b946c1146dcea77c9c399d39601aaa",
                    "generator_version": version,
                    "server_binary_sha256": hashlib.sha256(server.read_bytes()).hexdigest(),
                    "rdb_format_version": 11,
                    "file": "empty.rdb",
                    "size_bytes": len(data),
                    "sha256": hashlib.sha256(data).hexdigest(),
                    "expected_keys": 0,
                    "databases_configured": 16,
                    "checksum_enabled": args.checksum == "enabled",
                    "generation": "Fresh isolated instance; INFO keyspace empty; SAVE; redis-check-rdb",
                }
                (args.output_dir / "manifest.json").write_text(
                    json.dumps(manifest, indent=2) + "\n", encoding="utf-8",
                )
                print(f"Generated {args.output_dir}: {len(data)} bytes; SHA256 {manifest['sha256']}")
            finally:
                if proc.poll() is None:
                    proc.terminate()
                    try:
                        proc.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                        proc.wait(timeout=5)


if __name__ == "__main__":
    main()
