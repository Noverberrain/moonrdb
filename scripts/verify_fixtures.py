"""Offline fixture identity checks. This does not parse RDB or implement CRC64."""

import hashlib
import json
from pathlib import Path


def verify(folder, checksum_enabled):
    manifest = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))
    data = (folder / "empty.rdb").read_bytes()
    checks = {
        "size": len(data) == manifest["size_bytes"],
        "sha256": hashlib.sha256(data).hexdigest() == manifest["sha256"],
        "header": data[:9] == b"REDIS0011",
        "EOF position": len(data) >= 18 and data[-9] == 255,
        "checksum mode": len(data) >= 18 and (data[-8:] != bytes(8)) == checksum_enabled
        and manifest["checksum_enabled"] == checksum_enabled,
        "reference": manifest["redis_version"] == "7.2.5"
        and manifest["upstream_commit"] == "f60370ce28b946c1146dcea77c9c399d39601aaa"
        and manifest["rdb_format_version"] == 11,
    }
    failures = [name for name, passed in checks.items() if not passed]
    if failures:
        raise SystemExit("Fixture verification failed: " + ", ".join(failures))
    print(f"{folder.name}: {len(checks)} identity checks passed ({len(data)} bytes).")


def main():
    root = Path(__file__).resolve().parents[1] / "fixtures"
    verify(root / "redis-7.2.5", True)
    verify(root / "redis-7.2.5-no-checksum", False)
    print("Identity checks only; RDB parsing and CRC64 are covered separately by MoonBit tests.")


if __name__ == "__main__":
    main()
