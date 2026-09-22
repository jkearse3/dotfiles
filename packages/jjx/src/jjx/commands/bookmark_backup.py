"""Preserve a remote jj bookmark without retaining divergent change IDs."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from collections.abc import Sequence
from datetime import UTC, datetime
from pathlib import Path
from typing import cast

from .process import capture_bytes
from .revsets import exact_string_pattern


COMMIT_ID_PATTERN = re.compile(r"[0-9a-f]{40}")
LOCAL_TARGET_TEMPLATE = (
    'if(!remote, if(conflict, "conflict\\n", normal_target.commit_id() ++ "\\n"))'
)
REMOTE_TARGET_TEMPLATE = (
    'if(remote, if(conflict, "conflict\\n", normal_target.commit_id() ++ "\\n"))'
)


class BookmarkBackupError(Exception):
    """A concise, user-facing bookmark backup failure."""


def _run(
    command: Sequence[str],
    *,
    cwd: Path | None = None,
) -> subprocess.CompletedProcess[bytes]:
    """Run COMMAND and capture its output, raising only when it cannot start."""
    return capture_bytes(command, error_type=BookmarkBackupError, cwd=cwd)


def _run_ok(command: Sequence[str], *, cwd: Path | None = None) -> str:
    """Run COMMAND and return decoded stdout or raise a user-facing failure."""
    result = _run(command, cwd=cwd)
    if result.returncode != 0:
        detail = os.fsdecode(result.stderr).strip()
        suffix = f": {detail}" if detail else ""
        raise BookmarkBackupError(f"{' '.join(command)} failed{suffix}")
    return os.fsdecode(result.stdout)


def _jj(*arguments: str, cwd: Path | None = None) -> str:
    """Run jj without snapshotting the working copy and return stdout."""
    return _run_ok(["jj", "--ignore-working-copy", *arguments], cwd=cwd)


def _bookmark_target(
    bookmark: str,
    *,
    remote: str | None = None,
    cwd: Path | None = None,
) -> str | None:
    """Resolve a bookmark target, returning None when it does not exist."""
    arguments = ["bookmark", "list", "--color=never"]
    template = LOCAL_TARGET_TEMPLATE
    display_name = bookmark
    if remote is not None:
        arguments.extend(["--remote", exact_string_pattern(remote)])
        template = REMOTE_TARGET_TEMPLATE
        display_name = f"{bookmark}@{remote}"
    arguments.extend(["--template", template, "--", exact_string_pattern(bookmark)])

    target = _jj(*arguments, cwd=cwd).strip()
    if not target:
        return None
    if target == "conflict":
        raise BookmarkBackupError(f"bookmark {display_name} is conflicted")
    if COMMIT_ID_PATTERN.fullmatch(target) is None:
        raise BookmarkBackupError(f"bookmark {display_name} has an invalid target")
    return target


def _backup_name(bookmark: str, created_at: datetime) -> str:
    """Return the private timestamp namespace for BOOKMARK."""
    timestamp = created_at.astimezone(UTC).strftime("%Y%m%dT%H%M%SZ")
    return f"backup-{timestamp}/{bookmark}"


def _ensure_backup_name_available(backup: str, *, cwd: Path | None = None) -> None:
    """Reject a backup name already present locally or on any remote."""
    existing = _jj(
        "--quiet",
        "bookmark",
        "list",
        "--all-remotes",
        "--color=never",
        "--template",
        'name ++ "\\n"',
        "--",
        exact_string_pattern(backup),
        cwd=cwd,
    ).strip()
    if existing:
        raise BookmarkBackupError(f"bookmark {backup} already exists")


def _log_commit_ids(revset: str, *, cwd: Path | None = None) -> list[str]:
    """Return full commit IDs selected by REVSET."""
    output = _jj(
        "log",
        "--no-graph",
        "--color=never",
        "-r",
        revset,
        "-T",
        'commit_id ++ "\\n"',
        cwd=cwd,
    )
    return output.splitlines()


def _single_revision(revset: str, *, cwd: Path | None = None) -> str:
    """Resolve REVSET to exactly one commit ID."""
    commits = _log_commit_ids(revset, cwd=cwd)
    if len(commits) != 1 or COMMIT_ID_PATTERN.fullmatch(commits[0]) is None:
        raise BookmarkBackupError(f"revset must resolve to one revision: {revset}")
    return commits[0]


def _duplicate_remote_only_revisions(
    local_target: str,
    remote_target: str,
    *,
    cwd: Path | None = None,
) -> str:
    """Duplicate remote-only history and return its single new tip commit ID."""
    remote_only_revset = f"{local_target}..{remote_target}"
    remote_only_commits = _log_commit_ids(remote_only_revset, cwd=cwd)
    if not remote_only_commits:
        return remote_target

    before_operation = _jj("op", "log", "--no-graph", "-n", "1", "-T", "id", cwd=cwd)
    _ = _jj("--quiet", "duplicate", "-r", remote_only_revset, cwd=cwd)

    new_revisions = f"visible() ~ at_operation({before_operation.strip()}, visible())"
    new_commits = _log_commit_ids(new_revisions, cwd=cwd)
    if len(new_commits) != len(remote_only_commits):
        raise BookmarkBackupError(
            "another repository operation raced with revision duplication"
        )

    backup_targets = _log_commit_ids(f"heads({new_revisions})", cwd=cwd)
    if (
        len(backup_targets) != 1
        or COMMIT_ID_PATTERN.fullmatch(backup_targets[0]) is None
    ):
        raise BookmarkBackupError("duplicated revisions did not produce one branch tip")
    return backup_targets[0]


def create_backup(
    bookmark: str,
    *,
    remote: str = "origin",
    created_at: datetime | None = None,
    cwd: Path | None = None,
) -> str:
    """Create and return an untracked local backup of BOOKMARK@REMOTE.

    Remote-only revisions are duplicated with fresh change IDs. A same-named
    local bookmark defines which remote revisions need duplication; otherwise,
    the remote branch is duplicated relative to `trunk()`.
    """
    if not bookmark:
        raise BookmarkBackupError("bookmark must not be empty")
    if not remote:
        raise BookmarkBackupError("remote must not be empty")

    _ = _jj(
        "--quiet",
        "git",
        "fetch",
        "--remote",
        exact_string_pattern(remote),
        "--branch",
        exact_string_pattern(bookmark),
        cwd=cwd,
    )
    local_target = _bookmark_target(bookmark, cwd=cwd)
    remote_target = _bookmark_target(bookmark, remote=remote, cwd=cwd)
    if remote_target is None:
        raise BookmarkBackupError(f"bookmark {bookmark}@{remote} does not exist")
    comparison_target = local_target or _single_revision("trunk()", cwd=cwd)

    backup = _backup_name(bookmark, created_at or datetime.now(UTC))
    _ensure_backup_name_available(backup, cwd=cwd)
    backup_target = _duplicate_remote_only_revisions(
        comparison_target,
        remote_target,
        cwd=cwd,
    )

    _ = _jj("--quiet", "bookmark", "create", backup, "-r", backup_target, cwd=cwd)
    try:
        _ = _jj(
            "--quiet",
            "bookmark",
            "untrack",
            exact_string_pattern(backup),
            "--remote",
            exact_string_pattern(remote),
            cwd=cwd,
        )
    except BookmarkBackupError as error:
        message = f"created backup {backup}, but could not untrack its remote counterpart; the backup was preserved: {error}"
        raise BookmarkBackupError(message) from error
    return backup


def create_parser(prog: str = "jjx bookmark backup") -> argparse.ArgumentParser:
    """Create the command-line argument parser."""
    parser = argparse.ArgumentParser(
        prog=prog,
        description=(
            "Duplicate remote-only revisions with fresh change IDs and preserve "
            "them under a private local backup bookmark."
        ),
    )
    _ = parser.add_argument(
        "bookmark", metavar="BOOKMARK", help="local bookmark to back up"
    )
    _ = parser.add_argument(
        "--remote",
        default="origin",
        metavar="REMOTE",
        help="remote containing the bookmark (default: origin)",
    )
    return parser


def main(
    arguments: Sequence[str] | None = None,
    *,
    prog: str = "jjx bookmark backup",
) -> int:
    """Run the command-line interface and return its exit status."""
    args = create_parser(prog).parse_args(arguments)
    try:
        backup = create_backup(
            cast(str, args.bookmark),
            remote=cast(str, args.remote),
        )
    except BookmarkBackupError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(backup)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
