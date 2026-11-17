"""Build an independent consumer against the packaged MoonRDB module."""
import argparse
import re
import subprocess
import tempfile
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
manifest = (root / "moon.mod").read_text(encoding="utf-8")
version_match = re.search(r'^version *= *"([0-9]+\.[0-9]+\.[0-9]+)" *$', manifest, re.MULTILINE)
if version_match is None:
    raise SystemExit("Expected a release version in moon.mod")
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--registry", metavar="VERSION", help="Install this version from Mooncakes in an independent module.")
args = parser.parse_args()
version = args.registry or version_match[1]
if args.registry is None:
    subprocess.run(["moon", "package"], cwd=root, check=True)
with tempfile.TemporaryDirectory(prefix="moonrdb-consumer-") as temp:
    workspace = Path(temp)
    library = workspace / "library"
    consumer = workspace / "consumer"
    consumer.mkdir()
    manifest = 'name = "local/consumer"\nversion = "0.1.0"\n'
    if args.registry is None:
        with zipfile.ZipFile(root / f"_build/publish/Noverberrain-moonrdb-{version}.zip") as archive:
            archive.extractall(library)
        library = next(library.rglob("moon.mod")).parent
        manifest += f'import {{ "Noverberrain/moonrdb@{version}" }}\n'
    (consumer / "moon.mod").write_text(manifest, encoding="utf-8")
    for name in ("moon.pkg", "main.mbt"):
        (consumer / name).write_bytes((root / "examples/parse" / name).read_bytes())
    if args.registry is None:
        subprocess.run(["moon", "work", "init"], cwd=workspace, check=True)
        subprocess.run(["moon", "work", "use", str(library), str(consumer)], cwd=workspace, check=True)
    else:
        subprocess.run(["moon", "add", f"Noverberrain/moonrdb@{version}"], cwd=consumer, check=True)
    subprocess.run(["moon", "run", ".", "--target", "native"], cwd=consumer, check=True)

    fixture = (root / "fixtures/redis-7.2.5-streams/streams.rdb").read_bytes()
    literal = "".join(f"\\x{byte:02x}" for byte in fixture)
    (consumer / "main.mbt").write_text(
        'fn main raise {\n'
        f'  let snapshot = @moonrdb.parse(b"{literal}")\n'
        '  guard snapshot.function_libraries.length() == 1 else { fail("expected one function library") }\n'
        '  guard snapshot.records.any(record => record is Stream(s) && s.entries.length() == 3) else { fail("expected Stream messages") }\n'
        '  guard snapshot.records.any(record => record is String(s) && s.database == 2UL && s.key == b"following" && s.value == b"still readable") else { fail("expected DB 2 String record") }\n'
        '  println("stream and function library parsed")\n'
        '}\n',
        encoding="utf-8",
    )
    subprocess.run(["moon", "run", ".", "--target", "native"], cwd=consumer, check=True)
