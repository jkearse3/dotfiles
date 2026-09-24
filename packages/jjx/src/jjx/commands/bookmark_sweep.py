"""Move a jj bookmark forward and remove the local bookmarks it passes."""

from __future__ import annotations

import argparse
import os
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import cast

from .process import checked_bytes
from .revsets import bookmark_revset, decode_json_string, exact_string_pattern


class SweepError(Exception):
    """A concise, user-facing sweep failure."""


def _run(command: Sequence[str], *, cwd: Path | None = None) -> bytes:
    """Run COMMAND and return stdout, raising a user-facing error on failure."""
    return checked_bytes(command, error_type=SweepError, cwd=cwd)


def _lines(command: Sequence[str], *, cwd: Path | None = None) -> list[str]:
    """Run COMMAND and decode its stdout as individual lines."""
    return os.fsdecode(_run(command, cwd=cwd)).splitlines()


def _resolve(revision: str, *, cwd: Path | None = None) -> str:
    """Resolve REVISION to exactly one jj commit ID."""
    commits = _lines(
        [
            "jj",
            "--no-pager",
            "--color=never",
            "log",
            "--no-graph",
            "-r",
            f"exactly(({revision}), 1)",
            "-T",
            'commit_id ++ "\\n"',
        ],
        cwd=cwd,
    )
    if len(commits) != 1:
        raise SweepError(f"revision must resolve to exactly one commit: {revision}")
    return commits[0]


def _has_revisions(revset: str, *, cwd: Path | None = None) -> bool:
    """Return whether REVSET contains at least one revision."""
    return bool(
        _run(
            [
                "jj",
                "--no-pager",
                "--color=never",
                "log",
                "--no-graph",
                "-r",
                revset,
                "-T",
                "commit_id",
            ],
            cwd=cwd,
        )
    )


def _resolve_bookmark(name: str, *, cwd: Path | None = None) -> str:
    """Resolve one exact local bookmark name to its commit ID."""
    bookmarks = _lines(
        [
            "jj",
            "bookmark",
            "list",
            "--ignore-working-copy",
            "-T",
            'if(!remote && present, json(name) ++ "\\n")',
        ],
        cwd=cwd,
    )
    names = [
        decode_json_string(
            bookmark, error_type=SweepError, context="bookmark name"
        )
        for bookmark in bookmarks
    ]
    if names.count(name) != 1:
        raise SweepError(f"not a local bookmark: {name}")
    return _resolve(bookmark_revset(name), cwd=cwd)


def _move_bookmark(
    name: str,
    target: str,
    *,
    allow_backwards: bool = False,
    cwd: Path | None = None,
) -> None:
    """Move the exact local bookmark NAME to TARGET."""
    command = [
        "jj",
        "bookmark",
        "move",
        exact_string_pattern(name),
        "--to",
        target,
    ]
    if allow_backwards:
        command.append("--allow-backwards")
    _ = _run(command, cwd=cwd)


def sweep(
    bookmark: str,
    target: str,
    *,
    forget: bool = False,
    dry_run: bool = False,
    cwd: Path | None = None,
) -> list[str]:
    """Move BOOKMARK forward to TARGET, removing the local bookmarks it passes.

    BOOKMARK must name exactly one local bookmark. TARGET is any revset that
    resolves to one commit descending from BOOKMARK through a merge-free
    first-parent chain. Every other local bookmark on `BOOKMARK..TARGET`,
    including one on TARGET itself, is deleted, or forgotten when FORGET is set.

    Returns the swept bookmark names in stack order, which is empty when the
    move passes no bookmarks. A dry run returns the same names without changing
    the repository. Raises SweepError when validation fails, or when cleanup
    fails after the move, in which case BOOKMARK is restored to its original
    target when possible.
    """
    bookmark_commit = _resolve_bookmark(bookmark, cwd=cwd)
    target_commit = _resolve(target, cwd=cwd)
    if bookmark_commit == target_commit:
        raise SweepError(f"{bookmark} already points to {target}")
    if not _has_revisions(f"{bookmark_commit} & ::{target_commit}", cwd=cwd):
        raise SweepError(f"{target} is not a descendant of {bookmark}")

    revisions = f"{bookmark_commit}..{target_commit}"
    if _has_revisions(f"({revisions}) ~ first_ancestors({target_commit})", cwd=cwd):
        raise SweepError("revisions to sweep do not form a first-parent stack")
    if _has_revisions(f"({revisions}) & merges()", cwd=cwd):
        raise SweepError("the swept range contains a merge revision")

    swept = _lines(
        [
            "jj",
            "--no-pager",
            "--color=never",
            "log",
            "--no-graph",
            "--reversed",
            "-r",
            revisions,
            "-T",
            'local_bookmarks.map(|b| json(b.name())).join("\\n") ++ if(local_bookmarks, "\\n")',
        ],
        cwd=cwd,
    )
    swept = [
        decode_json_string(name, error_type=SweepError, context="bookmark name")
        for name in swept
        if name != ""
    ]
    swept = [name for name in swept if name != bookmark]
    if dry_run:
        return swept

    _move_bookmark(bookmark, target_commit, cwd=cwd)
    if len(swept) == 0:
        return swept

    action = "forget" if forget else "delete"
    try:
        _ = _run(
            [
                "jj",
                "bookmark",
                action,
                "--",
                *map(exact_string_pattern, swept),
            ],
            cwd=cwd,
        )
    except SweepError as cleanup_error:
        try:
            _move_bookmark(bookmark, bookmark_commit, allow_backwards=True, cwd=cwd)
        except SweepError as rollback_error:
            message = f"bookmark cleanup failed after moving {bookmark}: {cleanup_error}; rollback also failed: {rollback_error}"
            raise SweepError(message) from cleanup_error
        message = f"bookmark cleanup failed after moving {bookmark}; restored its original target: {cleanup_error}"
        raise SweepError(message) from cleanup_error
    return swept


def create_parser(prog: str = "jjx bookmark sweep") -> argparse.ArgumentParser:
    """Create the command-line argument parser."""
    parser = argparse.ArgumentParser(
        prog=prog,
        description=(
            "Move a bookmark forward to a target revision, deleting the bookmarks "
            "it passes."
        ),
    )
    _ = parser.add_argument("bookmark", metavar="BOOKMARK", help="bookmark to move")
    _ = parser.add_argument(
        "-t",
        "--to",
        required=True,
        metavar="REVSET",
        help="revision to move the bookmark to",
    )
    _ = parser.add_argument(
        "--forget",
        action="store_true",
        help="forget swept bookmarks instead of recording remote deletions",
    )
    _ = parser.add_argument(
        "--dry-run",
        action="store_true",
        help="show the sweep plan without changing it",
    )
    return parser


def main(
    arguments: Sequence[str] | None = None,
    *,
    prog: str = "jjx bookmark sweep",
) -> int:
    """Run the command-line interface and return its exit status."""
    args = create_parser(prog).parse_args(arguments)
    try:
        bookmark = cast(str, args.bookmark)
        target = cast(str, args.to)
        forget = cast(bool, args.forget)
        dry_run = cast(bool, args.dry_run)
        swept = sweep(bookmark, target, forget=forget, dry_run=dry_run)
    except SweepError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    action = (
        "Would forget"
        if dry_run and forget
        else "Would delete"
        if dry_run
        else "Forgot"
        if forget
        else "Deleted"
    )
    print(f"{'Would move' if dry_run else 'Moved'} {bookmark} to {target}")
    if len(swept) != 0:
        print(f"{action} bookmarks: {', '.join(swept)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
