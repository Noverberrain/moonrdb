"""Build an independent consumer against the packaged MoonRDB module."""
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
version = version_match[1]
subprocess.run(["moon", "package"], cwd=root, check=True)
with tempfile.TemporaryDirectory(prefix="moonrdb-consumer-") as temp:
    workspace = Path(temp)
    library = workspace / "library"
    consumer = workspace / "consumer"
    consumer.mkdir()
    with zipfile.ZipFile(root / f"_build/publish/Noverberrain-moonrdb-{version}.zip") as archive:
        archive.extractall(library)
    library = next(library.rglob("moon.mod")).parent
    (consumer / "moon.mod").write_text(
        f'name = "local/consumer"\nversion = "0.1.0"\nimport {{ "Noverberrain/moonrdb@{version}" }}\n',
        encoding="utf-8",
    )
    for name in ("moon.pkg", "main.mbt"):
        (consumer / name).write_bytes((root / "examples/parse" / name).read_bytes())
    subprocess.run(["moon", "work", "init"], cwd=workspace, check=True)
    subprocess.run(["moon", "work", "use", str(library), str(consumer)], cwd=workspace, check=True)
    subprocess.run(["moon", "run", ".", "--target", "native"], cwd=consumer, check=True)

    fixture = (root / "fixtures/redis-7.2.5-streams/streams.rdb").read_bytes()
    literal = "".join(f"\\x{byte:02x}" for byte in fixture)
    (consumer / "main.mbt").write_text(
        'fn main raise {\n'
        f'  let snapshot = @moonrdb.parse(b"{literal}")\n'
        '  guard snapshot.function_libraries.length() == 1 else { fail("expected one function library") }\n'
        '  guard snapshot.records.any(record => record is Stream(_)) else { fail("expected a Stream record") }\n'
        '  println("stream and function library parsed")\n'
        '}\n',
        encoding="utf-8",
    )
    subprocess.run(["moon", "run", ".", "--target", "native"], cwd=consumer, check=True)
