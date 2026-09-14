#!/usr/bin/env python3

"""Merge tracked fallback preferences into Hunk's writable user config."""

from __future__ import annotations

import copy
import os
import stat
import sys
import tempfile
from pathlib import Path

import tomlkit
from tomlkit.toml_document import TOMLDocument


def parse_toml(path: Path) -> TOMLDocument:
    """Parse a TOML document, identifying its path in parse failures."""
    try:
        return tomlkit.parse(path.read_text(encoding="utf-8"))
    except Exception as error:
        raise RuntimeError(f"failed to parse TOML from {path}: {error}") from error


def merge_missing_top_level_defaults(
    live_document: TOMLDocument,
    defaults_document: TOMLDocument,
) -> bool:
    """Add absent top-level defaults without replacing user-owned values."""
    changed = False
    for key in defaults_document:
        if key in live_document:
            continue

        live_document.add(key, copy.deepcopy(defaults_document.item(key)))
        changed = True

    return changed


def write_atomic(path: Path, content: str, mode: int) -> None:
    """Atomically replace a regular config while preserving its file mode."""
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary_path = Path(temporary_name)

    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as temporary_file:
            temporary_file.write(content)
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        temporary_path.chmod(mode)
        temporary_path.replace(path)
    finally:
        temporary_path.unlink(missing_ok=True)


def merge_hunk_config(live_path: Path, defaults_path: Path) -> None:
    """Apply missing defaults while leaving symlinks and existing values alone."""
    defaults_document = parse_toml(defaults_path)

    if live_path.is_symlink():
        return

    if live_path.exists() and not live_path.is_file():
        raise RuntimeError(f"refusing to replace non-file Hunk config at {live_path}")

    if not live_path.exists():
        write_atomic(live_path, defaults_path.read_text(encoding="utf-8"), 0o600)
        return

    live_document = parse_toml(live_path)
    if not merge_missing_top_level_defaults(live_document, defaults_document):
        return

    live_mode = stat.S_IMODE(live_path.stat().st_mode)
    write_atomic(live_path, tomlkit.dumps(live_document), live_mode)


def main(arguments: list[str]) -> int:
    """Run the merge command with live-config and defaults-file arguments."""
    if len(arguments) != 3:
        print("usage: hunk-config-merge <live-config> <defaults-file>", file=sys.stderr)
        return 2

    try:
        merge_hunk_config(Path(arguments[1]), Path(arguments[2]))
    except Exception as error:
        print(f"hunk-config-merge: {error}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
