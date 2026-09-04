#!/usr/bin/env python3
"""Create or verify SHA-256 manifests for the maintained EA source set."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import sys


PROJECT_ROOT = Path(__file__).resolve().parent.parent
MAIN_SOURCE = PROJECT_ROOT / "EA_交易托管系统_v1.56.mq5"


def source_files() -> list[Path]:
    files = [MAIN_SOURCE]
    files.extend(sorted((PROJECT_ROOT / "Include").rglob("*.mqh")))
    missing = [path for path in files if not path.is_file()]
    if missing:
        raise FileNotFoundError("Missing maintained source: " + ", ".join(map(str, missing)))
    return files


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest().upper()


def manifest_lines() -> list[str]:
    return [f"{digest(path)}  {path.relative_to(PROJECT_ROOT).as_posix()}" for path in source_files()]


def verify(manifest: Path) -> int:
    expected: dict[str, str] = {}
    for number, raw in enumerate(manifest.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        try:
            checksum, relative = line.split(maxsplit=1)
        except ValueError as exc:
            raise ValueError(f"Invalid manifest line {number}: {raw!r}") from exc
        expected[relative.strip()] = checksum.upper()

    actual = {path.relative_to(PROJECT_ROOT).as_posix(): digest(path) for path in source_files()}
    ok = True
    for relative in sorted(set(expected) | set(actual)):
        if expected.get(relative) != actual.get(relative):
            print(f"MISMATCH {relative}: expected={expected.get(relative)} actual={actual.get(relative)}")
            ok = False
    if ok:
        print(f"OK: {len(actual)} maintained source files match {manifest}")
        return 0
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", type=Path, help="Write the current manifest to this path.")
    parser.add_argument("--verify", type=Path, help="Verify the current sources against a manifest.")
    args = parser.parse_args()

    if args.write and args.verify:
        parser.error("choose either --write or --verify")
    if args.verify:
        return verify(args.verify.resolve())
    lines = manifest_lines()
    if args.write:
        target = args.write.resolve()
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(f"WROTE: {target}")
    else:
        print("\n".join(lines))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(2)
