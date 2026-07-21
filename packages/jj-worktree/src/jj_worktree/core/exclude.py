from __future__ import annotations

import errno
import fcntl
import os
import stat
import tempfile
from collections.abc import Generator
from contextlib import contextmanager
from pathlib import Path

from . import process
from .process import WorktreeError
from .repository import MANAGED_ROOT_NAME, Repository


MANAGED_IGNORE_RULE = b"/.jj-worktrees/"
MANAGED_GITIGNORE_RULE = b"*"
EXCLUDE_LOCK_NAME = "exclude.jj-worktree.lock"


def normalized_exclude(original: bytes) -> bytes:
    lines = original.splitlines(keepends=True)
    retained = [line for line in lines if line.rstrip(b"\r\n") != MANAGED_IGNORE_RULE]
    if retained and not retained[-1].endswith((b"\n", b"\r")):
        retained[-1] += b"\n"
    retained.append(MANAGED_IGNORE_RULE + b"\n")
    return b"".join(retained)


def normalized_gitignore(original: bytes) -> bytes:
    lines = original.splitlines(keepends=True)
    retained = [line for line in lines if line.rstrip(b"\r\n") != MANAGED_GITIGNORE_RULE]
    if retained and not retained[-1].endswith((b"\n", b"\r")):
        retained[-1] += b"\n"
    retained.append(MANAGED_GITIGNORE_RULE + b"\n")
    return b"".join(retained)


def write_atomic(path: Path, content: bytes, mode: int) -> None:
    temporary_path: Path | None = None
    try:
        descriptor, temporary_name = tempfile.mkstemp(prefix="exclude.", dir=path.parent)
        temporary_path = Path(temporary_name)
        with os.fdopen(descriptor, "wb") as temporary:
            _ = temporary.write(content)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.chmod(temporary_path, mode)
        os.replace(temporary_path, path)
    except OSError as error:
        raise WorktreeError(f"could not update {path}: {error}") from error
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


@contextmanager
def locked_exclude(common_git: Path) -> Generator[Path, None, None]:
    info = common_git / "info"
    try:
        mode = info.lstat().st_mode
    except OSError as error:
        raise WorktreeError(f"cannot inspect {info}: {error}") from error
    if not stat.S_ISDIR(mode):
        raise WorktreeError(f"{info} is not a directory")
    lock = info / EXCLUDE_LOCK_NAME
    descriptor = -1
    try:
        descriptor = os.open(lock, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise WorktreeError(f"{lock} is not a regular file")
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            if error.errno in {errno.EACCES, errno.EAGAIN}:
                raise WorktreeError("another initialization is already running") from error
            raise
        yield info / "exclude"
    except WorktreeError:
        raise
    except OSError as error:
        raise WorktreeError(f"could not lock {lock}: {error}") from error
    finally:
        if descriptor >= 0:
            os.close(descriptor)


def is_ignored(primary: Path, path: Path) -> bool:
    try:
        relative = path.relative_to(primary)
    except ValueError:
        return False
    result = process.run(
        ["git", "-C", os.fspath(primary), "check-ignore", "--quiet", "--no-index", "--", os.fspath(relative)]
    )
    if result.returncode not in {0, 1}:
        detail = os.fsdecode(result.stderr).strip()
        raise WorktreeError(f"could not verify managed-root exclusion: {detail}")
    return result.returncode == 0


def is_jj_ignored(primary: Path) -> bool:
    output = process.checked(
        [
            "jj",
            "--no-pager",
            "--color=never",
            "--no-integrate-operation",
            "-R",
            os.fspath(primary),
            "file",
            "list",
            f'root:"{MANAGED_ROOT_NAME}"',
        ],
        label="jj managed-root exclusion verification",
    )
    return not output


def initialize_repository(repository: Repository) -> Path:
    with locked_exclude(repository.common_git) as exclude:
        try:
            exclude_mode = exclude.lstat().st_mode
            existed = True
        except FileNotFoundError:
            exclude_mode = 0o644
            existed = False
        except OSError as error:
            raise WorktreeError(f"cannot inspect {exclude}: {error}") from error
        if existed and not stat.S_ISREG(exclude_mode):
            raise WorktreeError(f"{exclude} is not a regular file")
        try:
            original = exclude.read_bytes() if existed else b""
        except OSError as error:
            raise WorktreeError(f"cannot read {exclude}: {error}") from error
        updated = normalized_exclude(original)
        changed = updated != original
        if changed:
            write_atomic(exclude, updated, stat.S_IMODE(exclude_mode))
        managed_root = repository.primary / MANAGED_ROOT_NAME
        created_root = False
        gitignore_changed = False
        gitignore_existed = False
        gitignore = managed_root / ".gitignore"
        original_gitignore = b""
        gitignore_mode = 0o644
        try:
            try:
                root_mode = managed_root.lstat().st_mode
            except FileNotFoundError:
                managed_root.mkdir()
                created_root = True
            else:
                if not stat.S_ISDIR(root_mode):
                    raise WorktreeError(f"{managed_root} is not a directory")
            try:
                gitignore_mode = gitignore.lstat().st_mode
                gitignore_existed = True
            except FileNotFoundError:
                gitignore_mode = 0o644
                gitignore_existed = False
            if gitignore_existed and not stat.S_ISREG(gitignore_mode):
                raise WorktreeError(f"{gitignore} is not a regular file")
            original_gitignore = gitignore.read_bytes() if gitignore_existed else b""
            updated_gitignore = normalized_gitignore(original_gitignore)
            gitignore_changed = updated_gitignore != original_gitignore
            if gitignore_changed:
                write_atomic(gitignore, updated_gitignore, stat.S_IMODE(gitignore_mode))
        except (OSError, WorktreeError) as error:
            if gitignore_changed:
                if gitignore_existed:
                    write_atomic(gitignore, original_gitignore, stat.S_IMODE(gitignore_mode))
                else:
                    gitignore.unlink(missing_ok=True)
            if changed:
                if existed:
                    write_atomic(exclude, original, stat.S_IMODE(exclude_mode))
                else:
                    exclude.unlink(missing_ok=True)
            if created_root:
                managed_root.rmdir()
            if isinstance(error, WorktreeError):
                raise
            raise WorktreeError(f"could not initialize {managed_root}: {error}") from error
        probe = repository.primary / MANAGED_ROOT_NAME / ".ignore-check"
        try:
            verified = is_ignored(repository.primary, probe) and is_jj_ignored(repository.primary)
        except WorktreeError as error:
            verification_error = error
            verified = False
        else:
            verification_error = None
        if not verified:
            if gitignore_changed:
                if gitignore_existed:
                    write_atomic(gitignore, original_gitignore, stat.S_IMODE(gitignore_mode))
                else:
                    gitignore.unlink(missing_ok=True)
            if changed:
                if existed:
                    write_atomic(exclude, original, stat.S_IMODE(exclude_mode))
                else:
                    exclude.unlink(missing_ok=True)
            if created_root:
                managed_root.rmdir()
            if verification_error is not None:
                raise verification_error
            raise WorktreeError("Git and jj did not confirm the complete managed root is ignored")
    return repository.primary
