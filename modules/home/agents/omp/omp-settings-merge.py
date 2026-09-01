#!/usr/bin/env python3

"""Merge fallback defaults into OMP's writable global YAML settings."""

from __future__ import annotations

import errno
import fcntl
import os
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time

_LOCK_RETRIES = 50
_LOCK_RETRY_DELAY_SECONDS = 0.1
_LINUX_LOCK_HIGH_SEED = 0x4F4D502D4C4F434B
_LINUX_LOCK_LOW_SEED = 0x50492D46494C454C
_YQ_MERGE_PROGRAM = """
def mapping:
  if . == null then {}
  elif type == "object" then .
  else error("OMP settings must be YAML mappings")
  end;
(.[0] | mapping) * (.[1] | mapping)
"""


def select_settings_path(agent_dir: Path) -> Path:
    """Match OMP's config.yml-first, existing-config.yaml fallback order."""
    canonical = agent_dir / "config.yml"
    fallback = agent_dir / "config.yaml"
    if canonical.exists() or canonical.is_symlink():
        return canonical
    if fallback.exists() or fallback.is_symlink():
        return fallback
    return canonical


def resolve_omp_yaml_write_path(settings_path: Path) -> Path:
    """Match OMP's realpath-first, immediate dangling-target resolution."""
    try:
        return settings_path.resolve(strict=True)
    except FileNotFoundError:
        pass

    if settings_path.is_symlink():
        immediate_target = Path(os.readlink(settings_path))
        if not immediate_target.is_absolute():
            immediate_target = settings_path.parent / immediate_target
        return Path(os.path.abspath(immediate_target))
    return Path(os.path.abspath(settings_path))


def writable_symlink_target(settings_path: Path) -> Path | None:
    """Return a symlink target OMP can rewrite without replacing the link."""
    if not settings_path.is_symlink():
        return None

    write_path = resolve_omp_yaml_write_path(settings_path)
    if not write_path.parent.is_dir() or not os.access(write_path.parent, os.W_OK):
        return None
    return write_path


def linux_lock_name(lock_path: Path) -> str:
    """Reproduce OMP's process-owned abstract-socket lock name on Linux."""
    import xxhash  # pyright: ignore[reportMissingImports]

    lock_bytes = str(lock_path).encode()
    high = xxhash.xxh64(lock_bytes, seed=_LINUX_LOCK_HIGH_SEED).intdigest()
    low = xxhash.xxh64(lock_bytes, seed=_LINUX_LOCK_LOW_SEED).intdigest()
    return f"omp-file-lock-{high:016x}{low:016x}"


@contextmanager
def omp_file_lock(write_path: Path) -> Iterator[None]:
    """Acquire the same bounded cross-process lock as OMP 18."""
    lock_path = Path(f"{os.path.abspath(write_path)}.lock")

    if sys.platform.startswith("linux"):
        lock_socket = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        abstract_address = f"\0{linux_lock_name(lock_path)}"
        for attempt in range(_LOCK_RETRIES):
            try:
                lock_socket.bind(abstract_address)
                break
            except OSError as error:
                if error.errno != errno.EADDRINUSE:
                    lock_socket.close()
                    raise
                if attempt + 1 == _LOCK_RETRIES:
                    lock_socket.close()
                    raise TimeoutError(f"failed to acquire OMP settings lock for {write_path}") from error
                time.sleep(_LOCK_RETRY_DELAY_SECONDS)
        try:
            yield
        finally:
            lock_socket.close()
        return

    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a+b") as lock_file:
        os.chmod(lock_path, 0o600)
        for attempt in range(_LOCK_RETRIES):
            try:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError as error:
                if attempt + 1 == _LOCK_RETRIES:
                    raise TimeoutError(f"failed to acquire OMP settings lock for {write_path}") from error
                time.sleep(_LOCK_RETRY_DELAY_SECONDS)
        try:
            yield
        finally:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)


def merge_yaml_settings(read_path: Path | None, write_path: Path, seed_path: Path) -> None:
    """Merge seed * live atomically, with the live mapping taking precedence."""
    write_path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=".omp-config.", dir=write_path.parent)
    temporary_path = Path(temporary_name)

    input_paths = [seed_path]
    if read_path is not None and read_path.exists():
        input_paths.append(read_path)

    try:
        with os.fdopen(descriptor, "wb") as temporary_file:
            subprocess.run(
                ["yq", "-e", "-y", "-s", _YQ_MERGE_PROGRAM, *map(str, input_paths)],
                check=True,
                stdout=temporary_file,
            )
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
            os.fchmod(temporary_file.fileno(), 0o600)
        os.replace(temporary_path, write_path)
    except BaseException:
        temporary_path.unlink(missing_ok=True)
        raise


def merge_omp_settings(agent_dir: Path, seed_path: Path) -> Path:
    """Select OMP's active file, preserve viable links, lock, and merge."""
    agent_dir.mkdir(parents=True, exist_ok=True)
    settings_path = select_settings_path(agent_dir)
    symlink_target = writable_symlink_target(settings_path)

    if symlink_target is not None:
        read_path = symlink_target
        write_path = symlink_target
        lock_required = True
    else:
        read_path = settings_path if settings_path.exists() else None
        write_path = settings_path
        # A read-only symlink cannot be locked or rewritten by OMP. Replace it
        # with a regular writable file without trying to lock its store target.
        lock_required = not settings_path.is_symlink()

    if lock_required:
        with omp_file_lock(write_path):
            merge_yaml_settings(read_path, write_path, seed_path)
    else:
        merge_yaml_settings(read_path, write_path, seed_path)
    return settings_path


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: omp-settings-merge <agent-dir> <seed-yaml>", file=sys.stderr)
        return 2

    merge_omp_settings(Path(sys.argv[1]), Path(sys.argv[2]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
