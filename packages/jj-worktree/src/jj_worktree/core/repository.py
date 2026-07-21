from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from . import process
from .process import WorktreeError


MANAGED_ROOT_NAME = ".jj-worktrees"


@dataclass(frozen=True)
class Repository:
    primary: Path
    current: Path
    common_git: Path
    current_git: Path


@dataclass(frozen=True)
class GitWorktree:
    path: Path
    git_dir: Path | None
    head: str
    detached: bool


def git_path(start: Path, *arguments: str) -> Path:
    value = process.single_line(
        process.checked(
            ["git", "-C", os.fspath(start), *arguments], label="git discovery"
        ),
        "git discovery",
    )
    try:
        path = Path(value)
        return (path if path.is_absolute() else start / path).resolve(strict=True)
    except (OSError, ValueError) as error:
        raise WorktreeError(f"git returned an unusable path: {value}") from error


def jj_path(start: Path, *arguments: str) -> Path:
    operation = f"jj {' '.join(arguments)}"
    value = process.single_line(
        process.checked(
            [
                "jj",
                "--no-pager",
                "--color=never",
                "--ignore-working-copy",
                "-R",
                os.fspath(start),
                *arguments,
            ],
            label=operation,
        ),
        operation,
    )
    try:
        return Path(value).resolve(strict=True)
    except (OSError, ValueError) as error:
        raise WorktreeError(f"jj returned an unusable path: {value}") from error


def same_file(first: Path, second: Path, message: str) -> None:
    try:
        matches = os.path.samefile(first, second)
    except OSError as error:
        raise WorktreeError(f"{message}: {error}") from error
    if not matches:
        raise WorktreeError(message)


def parse_worktrees(repository: Path) -> list[GitWorktree]:
    output = process.checked(
        ["git", "-C", os.fspath(repository), "worktree", "list", "--porcelain", "-z"],
        label="git worktree list",
    )
    records: list[GitWorktree] = []
    for raw_record in output.split(b"\0\0"):
        if not raw_record:
            continue
        fields: dict[bytes, bytes] = {}
        flags: set[bytes] = set()
        for line in raw_record.strip(b"\0").split(b"\0"):
            key, separator, value = line.partition(b" ")
            if separator:
                fields[key] = value
            else:
                flags.add(key)
        try:
            path = Path(os.fsdecode(fields[b"worktree"]))
            if not path.is_absolute():
                raise ValueError("relative worktree path")
            head = os.fsdecode(fields[b"HEAD"])
            private_git = git_path(path, "rev-parse", "--absolute-git-dir") if path.exists() else None
        except (KeyError, OSError, ValueError, UnicodeError) as error:
            raise WorktreeError("git returned malformed worktree metadata") from error
        records.append(GitWorktree(path, private_git, head, b"detached" in flags))
    if not records:
        raise WorktreeError("git returned no worktree metadata")
    return records


def discover_repository(start: Path | None = None) -> Repository:
    requested = Path.cwd() if start is None else start
    current = git_path(requested, "rev-parse", "--show-toplevel")
    current_git = git_path(current, "rev-parse", "--absolute-git-dir")
    common_git = git_path(current, "rev-parse", "--git-common-dir")
    worktrees = parse_worktrees(current)
    primary = worktrees[0].path
    if worktrees[0].git_dir is None or worktrees[0].git_dir != common_git:
        raise WorktreeError("primary worktree does not own the common Git directory")
    matching = [record for record in worktrees if record.path == current]
    if len(matching) != 1 or matching[0].git_dir != current_git:
        raise WorktreeError("current worktree identity is not recorded by Git")
    same_file(jj_path(current, "root"), current, "jj root does not match Git worktree")
    same_file(
        jj_path(current, "git", "root"),
        current_git,
        "jj repository is not colocated with this Git worktree",
    )
    if current != primary:
        try:
            relative = current.relative_to(primary / MANAGED_ROOT_NAME)
        except ValueError as error:
            raise WorktreeError("linked worktree is outside the managed root") from error
        if len(relative.parts) != 1:
            raise WorktreeError("linked worktree is not a direct managed child")
    return Repository(primary, current, common_git, current_git)
