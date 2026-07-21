from __future__ import annotations

import os
from pathlib import Path

from ..core import managed, process, repository
from ..core.process import WorktreeError


def _jj_working_copy_is_removable(path: Path) -> None:
    _ = process.checked(
        ["jj", "--no-pager", "--color=never", "-R", os.fspath(path), "status"],
        label="jj working-copy snapshot",
    )
    output = managed.jj_output(
        path,
        "log",
        "--no-graph",
        "-r",
        "@",
        "-T",
        'if(empty, "empty", "non-empty") ++ "\\0" ++ description',
    )
    state, separator, description = output.partition(b"\0")
    if not separator or state != b"empty" or description:
        raise WorktreeError("jj working-copy commit is non-empty or described")


def remove_worktree(name: str, *, confirm: bool = False, start: Path | None = None) -> None:
    if not confirm:
        raise WorktreeError("removal requires --yes confirmation")
    managed.validate_name(name)
    repo = repository.discover_repository(start)
    item = managed.record(repo, name)
    if item.status != "ok" or item.path is None:
        raise WorktreeError(f"worktree {name!r} is {item.status}")
    path = item.path
    if path in {repo.primary, repo.current}:
        raise WorktreeError("cannot remove the primary or current worktree")
    _jj_working_copy_is_removable(path)
    status = process.checked(
        ["git", "-C", os.fspath(path), "status", "--porcelain=v1", "-z"],
        label="git worktree cleanliness check",
    )
    if status:
        raise WorktreeError("Git worktree has active changes")
    result = process.run(["git", "-C", os.fspath(repo.primary), "worktree", "remove", os.fspath(path)])
    files_present = path.exists()
    metadata_present = any(worktree.path == path for worktree in repository.parse_worktrees(repo.primary))
    if result.returncode != 0 or files_present or metadata_present:
        result_state = "failed" if result.returncode != 0 else "reported success"
        file_state = "present" if files_present else "missing"
        metadata_state = "present" if metadata_present else "missing"
        detail = os.fsdecode(result.stderr).strip()
        suffix = f": {detail}" if detail else ""
        message = f"Git worktree removal {result_state}; files are {file_state}"
        raise WorktreeError(f"{message} and metadata is {metadata_state}{suffix}")
