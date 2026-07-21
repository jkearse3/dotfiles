from __future__ import annotations

import os
import stat
from dataclasses import dataclass
from pathlib import Path

from . import exclude, process, repository
from .process import WorktreeError
from .repository import GitWorktree, MANAGED_ROOT_NAME, Repository


@dataclass(frozen=True)
class WorktreeRecord:
    name: str
    path: Path | None
    status: str


def validate_name(name: str) -> None:
    separators = {os.sep}
    if os.altsep is not None:
        separators.add(os.altsep)
    if (
        not name
        or name in {".", ".."}
        or Path(name).is_absolute()
        or any(separator in name for separator in separators)
        or any(ord(character) < 32 or ord(character) == 127 for character in name)
    ):
        raise WorktreeError(f"unsafe worktree name: {name!r}")


def destination(repo: Repository, name: str) -> tuple[Path, Path]:
    root = repo.primary / MANAGED_ROOT_NAME
    target = root / name
    try:
        expected_root = repo.primary.resolve(strict=True) / MANAGED_ROOT_NAME
        resolved_root = root.resolve(strict=root.exists())
        resolved_target = target.resolve(strict=False)
    except (OSError, ValueError) as error:
        raise WorktreeError(f"cannot resolve managed destination: {error}") from error
    if root.is_symlink() or resolved_root != expected_root:
        raise WorktreeError("managed root must not be a symlink")
    if root.exists() and not root.is_dir():
        raise WorktreeError("managed root is not a directory")
    if resolved_target.parent != expected_root:
        raise WorktreeError("worktree destination is outside the managed root")
    try:
        _ = target.lstat()
    except FileNotFoundError:
        pass
    except OSError as error:
        raise WorktreeError(f"cannot inspect worktree destination: {error}") from error
    else:
        raise WorktreeError(f"worktree destination already exists: {target}")
    return root, target


def jj_output(repo: Path, *arguments: str) -> bytes:
    return process.checked(
        ["jj", "--no-pager", "--color=never", "--ignore-working-copy", "-R", os.fspath(repo), *arguments],
        label=f"jj {' '.join(arguments)}",
    )


def validate_attached_jj(target: Path, private_git: Path) -> None:
    repository.same_file(repository.jj_path(target, "root"), target, "attached jj root does not match the Git worktree")
    repository.same_file(
        repository.jj_path(target, "git", "root"),
        private_git,
        "attached jj repository does not use the private Git directory",
    )


def record(repo: Repository, name: str, worktrees: list[GitWorktree] | None = None) -> WorktreeRecord:
    matches: list[GitWorktree] = []
    malformed = False
    root = repo.primary / MANAGED_ROOT_NAME
    for worktree in worktrees if worktrees is not None else repository.parse_worktrees(repo.current):
        try:
            relative = worktree.path.relative_to(root)
        except ValueError:
            if worktree.git_dir is not None and worktree.git_dir.name == name:
                malformed = True
            continue
        if len(relative.parts) == 1 and relative.name == name:
            matches.append(worktree)
    if len(matches) != 1:
        return WorktreeRecord(name, None, "foreign" if malformed else "missing")
    match = matches[0]
    if match.git_dir is None or not match.path.exists():
        return WorktreeRecord(name, match.path, "stale")
    try:
        if stat.S_ISLNK(match.path.lstat().st_mode):
            return WorktreeRecord(name, match.path, "malformed")
    except OSError:
        return WorktreeRecord(name, match.path, "stale")
    if match.git_dir.parent.parent != repo.common_git:
        return WorktreeRecord(name, match.path, "foreign")
    if not match.detached:
        return WorktreeRecord(name, match.path, "attached")
    if not exclude.is_ignored(repo.primary, match.path):
        return WorktreeRecord(name, match.path, "unignored")
    try:
        discovered = repository.discover_repository(match.path)
    except WorktreeError:
        return WorktreeRecord(name, match.path, "malformed")
    if discovered.common_git != repo.common_git:
        return WorktreeRecord(name, match.path, "foreign")
    if discovered.current != match.path or discovered.current_git != match.git_dir:
        return WorktreeRecord(name, match.path, "malformed")
    return WorktreeRecord(name, match.path, "ok")
