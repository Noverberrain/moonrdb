"""Build an independent consumer against the packaged MoonRDB module."""
import subprocess
import tempfile
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
subprocess.run(["moon", "package"], cwd=root, check=True)
with tempfile.TemporaryDirectory(prefix="moonrdb-consumer-") as temp:
    workspace = Path(temp)
    library = workspace / "library"
    consumer = workspace / "consumer"
    consumer.mkdir()
    with zipfile.ZipFile(root / "_build/publish/Noverberrain-moonrdb-0.1.0.zip") as archive:
        archive.extractall(library)
    library = next(library.rglob("moon.mod")).parent
    (consumer / "moon.mod").write_text(
        'name = "local/consumer"\nversion = "0.1.0"\nimport { "Noverberrain/moonrdb@0.1.0" }\n',
        encoding="utf-8",
    )
    for name in ("moon.pkg", "main.mbt"):
        (consumer / name).write_bytes((root / "examples/parse" / name).read_bytes())
    subprocess.run(["moon", "work", "init"], cwd=workspace, check=True)
    subprocess.run(["moon", "work", "use", str(library), str(consumer)], cwd=workspace, check=True)
    subprocess.run(["moon", "run", ".", "--target", "native"], cwd=consumer, check=True)
