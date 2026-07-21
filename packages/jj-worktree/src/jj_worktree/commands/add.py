from __future__ import annotations

import json
import os
from pathlib import Path

from ..core import exclude, managed, process, repository
from ..core.process import WorktreeError
from ..core.repository import Repository


def _resolve_revision(repo: Path, name: str, revision: str | None) -> str:
    expression = f"bookmarks(exact:{json.dumps(name, ensure_ascii=False)})" if revision is None else f"({revision})"
    output = managed.jj_output(
        repo,
        "log",
        "--no-graph",
        "-r",
        f"exactly({expression}, 1)",
        "-T",
        'commit_id ++ "\\n"',
    )
    commits = output.splitlines()
    if len(commits) != 1 or not commits[0]:
        raise WorktreeError("revision did not resolve to exactly one commit")
    return os.fsdecode(commits[0])


def _rollback_add(repo: Repository, destination: Path) -> str | None:
    result = process.run(
        ["git", "-C", os.fspath(repo.primary), "worktree", "remove", "--force", os.fspath(destination)]
    )
    if result.returncode == 0:
        return None
    detail = os.fsdecode(result.stderr).strip()
    return detail or "Git could not remove partial worktree"


def add_worktree(name: str, revision: str | None = None, start: Path | None = None) -> Path:
    managed.validate_name(name)
    repo = repository.discover_repository(start)
    root, destination = managed.destination(repo, name)
    existing_worktrees = repository.parse_worktrees(repo.current)
    for record in existing_worktrees:
        if record.path == destination or (record.git_dir is not None and record.git_dir.name == name):
            raise WorktreeError(f"worktree name or path already exists: {name}")
    commit = _resolve_revision(repo.current, name, revision)
    _ = exclude.initialize_repository(repo)
    if not exclude.is_ignored(repo.primary, destination):
        raise WorktreeError(f"worktree destination is not ignored: {destination}")
    try:
        root.mkdir(exist_ok=True)
    except OSError as error:
        raise WorktreeError(f"could not create managed root: {error}") from error
    created = False
    try:
        result = process.run(
            ["git", "-C", os.fspath(repo.primary), "worktree", "add", "--detach", os.fspath(destination), commit]
        )
        if result.returncode != 0:
            created = any(record.path == destination for record in repository.parse_worktrees(repo.primary))
            detail = os.fsdecode(result.stderr).strip()
            suffix = f": {detail}" if detail else ""
            raise WorktreeError(f"Git worktree creation failed{suffix}")
        created = True
        matches = [record for record in repository.parse_worktrees(repo.primary) if record.path == destination]
        if len(matches) != 1 or not matches[0].detached:
            raise WorktreeError("created Git worktree identity failed validation")
        private_git = matches[0].git_dir
        if private_git is None:
            raise WorktreeError("created worktree has no private Git directory")
        _ = process.checked(
            ["jj", "git", "init", f"--git-repo={private_git}", "."],
            cwd=destination,
            label="jj private-Git-directory initialization",
        )
        managed.validate_attached_jj(destination, private_git)
        discovered = repository.discover_repository(destination)
        if discovered.common_git != repo.common_git or discovered.current_git != private_git:
            raise WorktreeError("created Git worktree identity failed validation")
    except (OSError, WorktreeError) as error:
        cleanup = _rollback_add(repo, destination) if created else None
        suffix = f"; rollback failed: {cleanup}" if cleanup else ""
        raise WorktreeError(f"could not initialize worktree {name!r}: {error}{suffix}") from error
    return destination
