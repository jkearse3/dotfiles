"""Private state paths. Refuse links, foreign ownership, and permissive leaf modes."""

import os
import stat
import tempfile
from pathlib import Path

from .config import xdg_root
from .errors import require


def registry_path() -> Path:
    return (
        xdg_root("XDG_STATE_HOME", Path.home() / ".local/state")
        / "pi-shepherd/registry.sqlite3"
    )


def lock_root() -> Path:
    fallback = Path(tempfile.gettempdir()).resolve() / f"pi-shepherd-{os.getuid()}"
    root = xdg_root("XDG_RUNTIME_DIR", fallback)
    if root != fallback:
        root = root / "pi-shepherd"
    return root / "locks"


def check_ancestors(path: Path) -> None:
    require(path.is_absolute(), "unsafe_path", "Private paths must be absolute")
    for ancestor in reversed(path.parents):
        if not ancestor.exists() and not ancestor.is_symlink():
            continue
        metadata = ancestor.lstat()
        sticky_system = metadata.st_uid == 0 and bool(metadata.st_mode & stat.S_ISVTX)
        require(
            stat.S_ISDIR(metadata.st_mode)
            and metadata.st_uid in (0, os.geteuid())
            and (not metadata.st_mode & 0o022 or sticky_system),
            "unsafe_path",
            "Unsafe private-state ancestor",
        )


def check_path(path: Path, *, directory: bool = False) -> None:
    check_ancestors(path)
    metadata = path.lstat()
    correct_type = (
        stat.S_ISDIR(metadata.st_mode) if directory else stat.S_ISREG(metadata.st_mode)
    )
    require(
        correct_type
        and metadata.st_uid == os.geteuid()
        and not metadata.st_mode & 0o077
        and (directory or metadata.st_nlink == 1),
        "unsafe_path",
        "Unsafe private-state path",
    )


def private_directory(path: Path) -> None:
    check_ancestors(path)
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    check_path(path, directory=True)


def private_file(path: Path) -> int:
    check_ancestors(path)
    descriptor = os.open(
        path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600
    )
    try:
        metadata = os.fstat(descriptor)
        require(
            stat.S_ISREG(metadata.st_mode)
            and metadata.st_uid == os.geteuid()
            and not metadata.st_mode & 0o077
            and metadata.st_nlink == 1,
            "unsafe_path",
            "Unsafe private-state file",
        )
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise
