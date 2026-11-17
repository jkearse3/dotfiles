"""Land a stack onto a jj bookmark, removing the local bookmarks it passes."""

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
    """A concise, user-facing land failure."""


def _run(command: Sequence[str], *, cwd: Path | None = None) -> bytes:
    """Run COMMAND and return stdout, raising a user-facing error on failure."""
    return checked_bytes(command, error_type=LandError, cwd=cwd)


def _lines(command: Sequence[str], *, cwd: Path | None = None) -> list[str]:
    """Run COMMAND and decode its stdout as individual lines."""
    return os.fsdecode(_run(command, cwd=cwd)).splitlines()


def _resolve(revision: str, *, cwd: Path | None = None) -> str:
    """Resolve REVISION to exactly one jj commit ID."""
    return _single_commit_field(revision, "commit_id", cwd=cwd)


def _short_change_id(revision: str, *, cwd: Path | None = None) -> str:
    """Resolve REVISION to the short change ID of exactly one commit."""
    return _single_commit_field(revision, "change_id.short()", cwd=cwd)


def _single_commit_field(
    revision: str, template: str, *, cwd: Path | None = None
) -> str:
    """Render TEMPLATE for the one commit REVISION resolves to."""
    values = _lines(
        [
            "jj",
            "--no-pager",
            "--color=never",
            "log",
            "--no-graph",
            "-r",
            f"exactly(({revision}), 1)",
            "-T",
            f'{template} ++ "\\n"',
        ],
        cwd=cwd,
    )
    if len(values) != 1:
        raise LandError(f"revision must resolve to exactly one commit: {revision}")
    return values[0]


def _advance_target(*, cwd: Path | None = None) -> str:
    """Return the revset `jj bookmark advance` moves bookmarks to by default."""
    revsets = _lines(
        ["jj", "config", "get", "revsets.bookmark-advance-to"],
        cwd=cwd,
    )
    if len(revsets) != 1 or revsets[0] == "":
        raise LandError("revsets.bookmark-advance-to must be a one-line revset")
    return revsets[0]


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


def _local_bookmark_names(*, cwd: Path | None = None) -> list[str]:
    """Return the names of present local bookmarks, one entry per bookmark."""
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
    return [
        decode_json_string(bookmark, error_type=LandError, context="bookmark name")
        for bookmark in bookmarks
    ]


def _resolve_bookmark(name: str, *, cwd: Path | None = None) -> str:
    """Resolve one exact local bookmark name to its commit ID."""
    if _local_bookmark_names(cwd=cwd).count(name) != 1:
        raise LandError(f"not a local bookmark: {name}")
    return _resolve(bookmark_revset(name), cwd=cwd)


def _trunk_bookmark(*, cwd: Path | None = None) -> str:
    """Return the local bookmark that `jjx bookmark land` moves by default.

    Collects the names of the local and remote bookmarks on `trunk()` and keeps
    those that exist as local bookmarks. Matching by name lets a local trunk
    bookmark that a land moved ahead of its unpushed remote still match, since
    `trunk()` follows the remote bookmark. Raises LandError, asking for
    `--onto`, unless exactly one name remains.
    """
    serialized_names = _lines(
        [
            "jj",
            "--no-pager",
            "--color=never",
            "log",
            "--no-graph",
            "-r",
            "trunk()",
            "-T",
            'local_bookmarks.map(|b| json(b.name()) ++ "\\n").join("") ++ remote_bookmarks.map(|b| json(b.name()) ++ "\\n").join("")',
        ],
        cwd=cwd,
    )
    trunk_names = list(
        dict.fromkeys(
            decode_json_string(name, error_type=LandError, context="bookmark name")
            for name in serialized_names
        )
    )

    local_names = set(_local_bookmark_names(cwd=cwd))
    candidates = [name for name in trunk_names if name in local_names]
    if len(candidates) == 1:
        return candidates[0]
    if len(candidates) == 0:
        found = f": {', '.join(trunk_names)}" if len(trunk_names) != 0 else ""
        raise LandError(
            f"no local bookmark matches the bookmarks on trunk(){found}; pass --onto BOOKMARK"
        )
    raise LandError(
        f"several local bookmarks match trunk(): {', '.join(candidates)}; pass --onto BOOKMARK"
    )


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
    target: str,
    onto: str,
    *,
    forget: bool = False,
    dry_run: bool = False,
    cwd: Path | None = None,
) -> list[str]:
    """Move the bookmark ONTO forward to TARGET, removing the bookmarks it passes.

    ONTO must name exactly one local bookmark. TARGET is any revset that
    resolves to one commit descending from ONTO through a merge-free
    first-parent chain. Every other local bookmark on `ONTO..TARGET`, including
    one on TARGET itself, is deleted, or forgotten when FORGET is set. Nothing
    is pushed or fetched.

    Returns the passed bookmark names in stack order, which is empty when the
    move passes no bookmarks. A dry run returns the same names without changing
    the repository. Raises LandError when validation fails, or when cleanup
    fails after the move, in which case ONTO is restored to its original target
    when possible.
    """
    onto_commit = _resolve_bookmark(onto, cwd=cwd)
    target_commit = _resolve(target, cwd=cwd)
    if onto_commit == target_commit:
        raise LandError(f"{onto} already points to {target}")
    if not _has_revisions(f"{onto_commit} & ::{target_commit}", cwd=cwd):
        raise LandError(f"{target} is not a descendant of {onto}")

    revisions = f"{onto_commit}..{target_commit}"
    if _has_revisions(f"({revisions}) ~ first_ancestors({target_commit})", cwd=cwd):
        raise LandError("revisions to land do not form a first-parent stack")
    if _has_revisions(f"({revisions}) & merges()", cwd=cwd):
        raise LandError("the landed range contains a merge revision")

    passed = _lines(
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
    passed = [
        decode_json_string(name, error_type=LandError, context="bookmark name")
        for name in passed
        if name != ""
    ]
    passed = [name for name in passed if name != onto]
    if dry_run:
        return passed

    _move_bookmark(onto, target_commit, cwd=cwd)
    if len(passed) == 0:
        return passed

    action = "forget" if forget else "delete"
    try:
        _ = _run(
            [
                "jj",
                "bookmark",
                action,
                "--",
                *map(exact_string_pattern, passed),
            ],
            cwd=cwd,
        )
    except LandError as cleanup_error:
        try:
            _move_bookmark(onto, onto_commit, allow_backwards=True, cwd=cwd)
        except LandError as rollback_error:
            message = f"bookmark cleanup failed after moving {onto}: {cleanup_error}; rollback also failed: {rollback_error}"
            raise LandError(message) from cleanup_error
        message = f"bookmark cleanup failed after moving {onto}; restored its original target: {cleanup_error}"
        raise LandError(message) from cleanup_error
    return passed


def create_parser(prog: str = "jjx bookmark land") -> argparse.ArgumentParser:
    """Create the command-line argument parser."""
    parser = argparse.ArgumentParser(
        prog=prog,
        description=(
            "Land a stack onto a bookmark: move the bookmark forward to REVSET "
            "and delete the local bookmarks it passes. REVSET defaults to "
            "revsets.bookmark-advance-to, the revision `jj bookmark advance` "
            "moves to, and the bookmark defaults to the local bookmark on "
            "trunk(). Nothing is pushed or fetched."
        ),
    )
    _ = parser.add_argument(
        "revset",
        metavar="REVSET",
        nargs="?",
        help="revision to land [default: revsets.bookmark-advance-to]",
    )
    _ = parser.add_argument(
        "-o",
        "--onto",
        metavar="BOOKMARK",
        help="local bookmark to move [default: the local bookmark on trunk()]",
    )
    _ = parser.add_argument(
        "--forget",
        action="store_true",
        help="forget passed bookmarks instead of recording remote deletions",
    )
    _ = parser.add_argument(
        "--dry-run",
        action="store_true",
        help="show the land plan without changing the repository",
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
        target = cast("str | None", args.revset)
        if target is None:
            target = _advance_target()
        onto = cast("str | None", args.onto)
        if onto is None:
            onto = _trunk_bookmark()
        forget = cast(bool, args.forget)
        dry_run = cast(bool, args.dry_run)
        target_change = _short_change_id(target)
        passed = land(target, onto, forget=forget, dry_run=dry_run)
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
    print(f"{'Would move' if dry_run else 'Moved'} {onto} to {target_change}")
    if len(passed) != 0:
        print(f"{action} bookmarks: {', '.join(passed)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
