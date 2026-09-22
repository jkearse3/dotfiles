"""Query bookmark placement and stacked-bookmark relationships."""

from __future__ import annotations

import argparse
import sys
from collections.abc import Callable, Sequence
from typing import cast

from .process import capture_text
from .revsets import decode_json_string


BookmarkStackEntry = tuple[str, ...]
QueryResult = str | Sequence[str] | None


class BookmarkQueryError(Exception):
    """A user-facing bookmark query failure."""


def nearest(revset: str) -> list[str]:
    """Return bookmark names on the nearest revisions selected by REVSET."""
    output = _jj_log(
        revset,
        'local_bookmarks.map(|b| json(b.name())).join("\\n") ++ if(local_bookmarks, "\\n")',
        failure="failed to find nearest bookmark",
    )
    return [
        decode_json_string(
            line, error_type=BookmarkQueryError, context="bookmark name"
        )
        for line in output.splitlines()
        if line
    ]


def current() -> str | None:
    """Return the unique nearest descendant bookmark, then ancestor bookmark."""
    for revset, direction in (
        ("roots(@:: & bookmarks())", "descendant"),
        ("heads(::@ & bookmarks())", "ancestor"),
    ):
        bookmarks = nearest(revset)
        if len(bookmarks) > 1:
            joined = "\n".join(bookmarks)
            raise BookmarkQueryError(f"multiple {direction} bookmarks found:\n{joined}")
        if bookmarks:
            return bookmarks[0]
    return None


def default() -> str:
    """Return the unique bookmark selected by trunk()."""
    bookmarks = nearest("trunk()")
    if not bookmarks:
        raise BookmarkQueryError("no trunk bookmark found")
    if len(bookmarks) > 1:
        raise BookmarkQueryError(
            "multiple trunk bookmarks found:\n" + "\n".join(bookmarks)
        )
    return bookmarks[0]


def stacked() -> list[str]:
    """Return first-parent bookmark entries from the current change toward trunk.

    Multiple bookmarks on one revision retain the historical comma-separated CLI
    representation. Internal consumers use structured entries so literal commas in
    bookmark names are not mistaken for separators.
    """
    return [",".join(entry) for entry in _stack_entries()]


def previous() -> str | None:
    """Return the sole bookmark at the preceding position in the current stack."""
    entries = _stack_entries()
    if not entries:
        return None

    selected = entries[1] if len(entries) > 1 else entries[0]
    if not selected:
        return None
    if len(selected) > 1:
        raise BookmarkQueryError("multiple bookmarks found:\n" + "\n".join(selected))
    return next(iter(selected))


def nearest_main(arguments: Sequence[str], *, prog: str) -> int:
    """Run the nearest-bookmark query CLI."""
    parser = argparse.ArgumentParser(prog=prog)
    _ = parser.add_argument("revset", metavar="REVSET")
    namespace = parser.parse_args(arguments)
    return _emit_query(lambda: nearest(cast(str, namespace.revset)))


def current_main(arguments: Sequence[str], *, prog: str) -> int:
    """Run the current-bookmark query CLI."""
    _parse_no_arguments(arguments, prog)
    return _emit_query(current)


def default_main(arguments: Sequence[str], *, prog: str) -> int:
    """Run the default-bookmark query CLI."""
    _parse_no_arguments(arguments, prog)
    return _emit_query(default)


def previous_main(arguments: Sequence[str], *, prog: str) -> int:
    """Run the previous-bookmark query CLI."""
    _parse_no_arguments(arguments, prog)
    return _emit_query(previous)


def stacked_main(arguments: Sequence[str], *, prog: str) -> int:
    """Run the stacked-bookmark query CLI."""
    _parse_no_arguments(arguments, prog)
    return _emit_query(stacked)


def _stack_entries() -> list[BookmarkStackEntry]:
    """Return losslessly framed bookmark names for each first-parent stack revision."""
    trunk = default()
    output = _jj_log(
        "first_ancestors(@) & (trunk()..@ | trunk()) & bookmarks() ~ @",
        'local_bookmarks.map(|b| json(b.name())).join("\\t") ++ "\\n"',
        failure="failed to list stacked bookmarks",
    )
    entries = [
        tuple(
            decode_json_string(
                name, error_type=BookmarkQueryError, context="bookmark name"
            )
            for name in line.split("\t")
            if name
        )
        for line in output.splitlines()
        if line
    ]
    if not any(trunk in entry for entry in entries):
        entries.append((trunk,))
    return entries


def _jj_log(revset: str, template: str, *, failure: str) -> str:
    """Run a read-only jj log query and return its standard output."""
    result = capture_text(
        [
            "jj",
            "--no-pager",
            "--color=never",
            "--ignore-working-copy",
            "log",
            "--no-graph",
            "-r",
            revset,
            "-T",
            template,
        ],
        error_type=BookmarkQueryError,
        capture_stderr=True,
    )
    if result.returncode != 0:
        raise BookmarkQueryError(failure)
    return result.stdout


def _parse_no_arguments(arguments: Sequence[str], prog: str) -> None:
    """Parse a leaf command whose only accepted option is help."""
    _ = argparse.ArgumentParser(prog=prog).parse_args(arguments)


def _emit_query(query: Callable[[], QueryResult]) -> int:
    """Print one query result and translate domain errors to an exit status."""
    try:
        result = query()
    except BookmarkQueryError as error:
        print(error, file=sys.stderr)
        return 1

    if isinstance(result, str):
        print(result)
    elif result:
        print("\n".join(result))
    return 0
