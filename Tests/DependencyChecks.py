import hashlib
import json
from pathlib import Path


def main():
    root = Path(__file__).resolve().parent.parent
    lock = json.loads((root / "docs/Expression.lock.json").read_text())
    for file in lock["files"]:
        path = root / file["path"]
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != file["sha256"]:
            raise SystemExit(f"Dependency checksum mismatch: {file['path']}")
    print(f"Expression {lock['version']} source and license match the dependency lock")


if __name__ == "__main__":
    main()
