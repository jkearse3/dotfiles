"""Land a bookmarked linear jj stack into a destination bookmark."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import cast


class LandError(Exception):
    """A concise, user-facing landing failure."""


def _run(command: Sequence[str], *, cwd: Path | None = None) -> bytes:
    """Run COMMAND and return stdout, raising a user-facing error on failure."""
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except OSError as error:
        raise LandError(f"could not run {command[0]}: {error}") from error
    if result.returncode != 0:
        detail = os.fsdecode(result.stderr).strip()
        suffix = f": {detail}" if detail else ""
        raise LandError(f"{' '.join(command)} failed{suffix}")
    return result.stdout


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
            ["jj", "--no-pager", "--color=never", "log", "--no-graph", "-r", revset, "-T", "commit_id"],
            cwd=cwd,
        )
    )


def _exact_bookmark(name: str) -> str:
    """Return a jj string pattern that matches one bookmark name exactly."""
    return f"exact:{json.dumps(name)}"


def _resolve_bookmark(name: str, role: str, *, cwd: Path | None = None) -> str:
    """Resolve one exact local bookmark name to its commit ID."""
    bookmarks = _lines(
        [
            "jj",
            "bookmark",
            "list",
            "--ignore-working-copy",
            "-T",
            'if(!remote && present, name ++ "\\n")',
        ],
        cwd=cwd,
    )
    if bookmarks.count(name) != 1:
        raise LandError(f"{role} must be a local bookmark: {name}")
    return _resolve(f"bookmarks({_exact_bookmark(name)})", cwd=cwd)


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
            'local_bookmarks.map(|b| b.name()).join("\\n") ++ if(local_bookmarks, "\\n")',
        ],
        cwd=cwd,
    )
    bookmarks = [name for name in bookmarks if name and name != into]
    if not bookmarks:
        raise LandError(f"no bookmarks found between {into} and {tip}")
    if dry_run:
        return bookmarks

    _ = _run(["jj", "bookmark", "move", _exact_bookmark(into), "--to", tip_commit], cwd=cwd)
    action = "forget" if forget else "delete"
    _ = _run(["jj", "bookmark", action, "--", *map(_exact_bookmark, bookmarks)], cwd=cwd)
    return bookmarks


def create_parser() -> argparse.ArgumentParser:
    """Create the command-line argument parser."""
    parser = argparse.ArgumentParser(
        prog="jj-bookmark-land",
        description=(
            "Fast-forward a destination bookmark through a bookmarked linear stack and "
            "remove every local bookmark in the landed range."
        ),
    )
    _ = parser.add_argument("tip", metavar="TIP", help="stack-tip bookmark")
    _ = parser.add_argument("--into", required=True, metavar="BOOKMARK", help="destination bookmark")
    _ = parser.add_argument(
        "--forget",
        action="store_true",
        help="forget landed bookmarks instead of recording remote deletions",
    )
    _ = parser.add_argument("--dry-run", action="store_true", help="show the landing plan without changing it")
    return parser


def main(arguments: Sequence[str] | None = None) -> int:
    """Run the command-line interface and return its exit status."""
    args = create_parser().parse_args(arguments)
    try:
        into = cast(str, args.into)
        tip = cast(str, args.tip)
        forget = cast(bool, args.forget)
        dry_run = cast(bool, args.dry_run)
        bookmarks = land(tip, into, forget=forget, dry_run=dry_run)
    except LandError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    action = "Would forget" if dry_run and forget else "Would delete" if dry_run else "Forgot" if forget else "Deleted"
    print(f"{'Would move' if dry_run else 'Moved'} {into} to {tip}")
    print(f"{action} bookmarks: {', '.join(bookmarks)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
