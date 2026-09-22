"""Land a bookmarked linear jj stack into a destination bookmark."""

from __future__ import annotations

import argparse
import os
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import cast

from .process import checked_bytes
from .revsets import bookmark_revset, decode_json_string, exact_string_pattern


class LandError(Exception):
    """A concise, user-facing landing failure."""


def _run(command: Sequence[str], *, cwd: Path | None = None) -> bytes:
    """Run COMMAND and return stdout, raising a user-facing error on failure."""
    return checked_bytes(command, error_type=LandError, cwd=cwd)


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
        raise LandError(f"revision must resolve to exactly one commit: {revision}")
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


def _resolve_bookmark(name: str, role: str, *, cwd: Path | None = None) -> str:
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
            bookmark, error_type=LandError, context="bookmark name"
        )
        for bookmark in bookmarks
    ]
    if names.count(name) != 1:
        raise LandError(f"{role} must be a local bookmark: {name}")
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


def land(
    tip: str,
    into: str,
    *,
    forget: bool = False,
    dry_run: bool = False,
    cwd: Path | None = None,
) -> list[str]:
    """Land TIP into a bookmark and return the cleaned-up bookmark names."""
    into_commit = _resolve_bookmark(into, "destination", cwd=cwd)
    tip_commit = _resolve_bookmark(tip, "tip", cwd=cwd)
    if into_commit == tip_commit:
        raise LandError("destination and tip already point to the same revision")
    if not _has_revisions(f"{into_commit} & ::{tip_commit}", cwd=cwd):
        raise LandError(f"{tip} is not a descendant of {into}")

    revisions = f"{into_commit}..{tip_commit}"
    if _has_revisions(f"({revisions}) ~ first_ancestors({tip_commit})", cwd=cwd):
        raise LandError("revisions to land do not form a first-parent stack")
    if _has_revisions(f"({revisions}) & merges()", cwd=cwd):
        raise LandError("the stack contains a merge revision")

    bookmarks = _lines(
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
    bookmarks = [
        decode_json_string(name, error_type=LandError, context="bookmark name")
        for name in bookmarks
        if name
    ]
    bookmarks = [name for name in bookmarks if name != into]
    if not bookmarks:
        raise LandError(f"no bookmarks found between {into} and {tip}")
    if dry_run:
        return bookmarks

    _move_bookmark(into, tip_commit, cwd=cwd)
    action = "forget" if forget else "delete"
    try:
        _ = _run(
            [
                "jj",
                "bookmark",
                action,
                "--",
                *map(exact_string_pattern, bookmarks),
            ],
            cwd=cwd,
        )
    except LandError as cleanup_error:
        try:
            _move_bookmark(into, into_commit, allow_backwards=True, cwd=cwd)
        except LandError as rollback_error:
            message = f"bookmark cleanup failed after moving {into}: {cleanup_error}; rollback also failed: {rollback_error}"
            raise LandError(message) from cleanup_error
        message = f"bookmark cleanup failed after moving {into}; restored its original target: {cleanup_error}"
        raise LandError(message) from cleanup_error
    return bookmarks


def create_parser(prog: str = "jjx bookmark land") -> argparse.ArgumentParser:
    """Create the command-line argument parser."""
    parser = argparse.ArgumentParser(
        prog=prog,
        description=(
            "Fast-forward a destination bookmark through a bookmarked linear stack and "
            "remove every local bookmark in the landed range."
        ),
    )
    _ = parser.add_argument("tip", metavar="TIP", help="stack-tip bookmark")
    _ = parser.add_argument(
        "-d",
        "--destination",
        required=True,
        metavar="BOOKMARK",
        help="destination bookmark",
    )
    _ = parser.add_argument(
        "--forget",
        action="store_true",
        help="forget landed bookmarks instead of recording remote deletions",
    )
    _ = parser.add_argument(
        "--dry-run",
        action="store_true",
        help="show the landing plan without changing it",
    )
    return parser


def main(
    arguments: Sequence[str] | None = None,
    *,
    prog: str = "jjx bookmark land",
) -> int:
    """Run the command-line interface and return its exit status."""
    args = create_parser(prog).parse_args(arguments)
    try:
        into = cast(str, args.destination)
        tip = cast(str, args.tip)
        forget = cast(bool, args.forget)
        dry_run = cast(bool, args.dry_run)
        bookmarks = land(tip, into, forget=forget, dry_run=dry_run)
    except LandError as error:
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
    print(f"{'Would move' if dry_run else 'Moved'} {into} to {tip}")
    print(f"{action} bookmarks: {', '.join(bookmarks)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
