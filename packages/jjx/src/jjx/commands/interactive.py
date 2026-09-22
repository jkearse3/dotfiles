"""Interactive bookmark and change selection workflows."""

from __future__ import annotations

import argparse
import subprocess
import sys
from collections.abc import Callable, Sequence
from typing import cast

from .process import capture_text, run_status
from .revsets import bookmark_revset, decode_json_string, exact_string_pattern


PUSH_SELECTOR_OPTIONS = {
    "-b",
    "--bookmark",
    "-t",
    "--tag",
    "--all",
    "--tracked",
    "--deleted",
    "-r",
    "--revision",
    "-c",
    "--change",
    "--named",
}


class InteractiveCommandError(Exception):
    """A user-facing failure to launch an interactive workflow dependency."""


def _report_launch_error(operation: Callable[[], int], *, prog: str) -> int:
    """Run OPERATION and report dependency launch failures for PROG."""
    try:
        return operation()
    except InteractiveCommandError as error:
        print(f"{prog}: {error}", file=sys.stderr)
        return 1


def _run(
    command: Sequence[str], *, stdin: str | None = None
) -> subprocess.CompletedProcess[str]:
    """Run COMMAND with inherited stderr and captured stdout."""
    return capture_text(command, error_type=InteractiveCommandError, stdin=stdin)


def _local_bookmarks() -> tuple[int, list[str]]:
    result = _run(
        [
            "jj",
            "bookmark",
            "list",
            "--color=never",
            "--template",
            'if(!remote, json(name) ++ "\\n")',
        ]
    )
    bookmarks = [
        decode_json_string(
            line, error_type=InteractiveCommandError, context="bookmark name"
        )
        for line in result.stdout.splitlines()
        if line
    ]
    return result.returncode, bookmarks


def _is_push_selector(argument: str) -> bool:
    option = argument.split("=", 1)[0]
    if option in PUSH_SELECTOR_OPTIONS:
        return True
    return any(
        option.startswith(short) and option != short
        for short in ("-b", "-t", "-r", "-c")
    )


def bookmark_push(arguments: Sequence[str], *, prog: str) -> int:
    """Select local bookmarks and push them with forwarded jj options."""
    return _report_launch_error(
        lambda: _bookmark_push(arguments, prog=prog),
        prog=prog,
    )


def _bookmark_push(arguments: Sequence[str], *, prog: str) -> int:
    """Select local bookmarks and push them with forwarded jj options."""
    if arguments in (["-h"], ["--help"]):
        print(f"usage: {prog} [<jj-git-push-option>...]")
        return 0
    for argument in arguments:
        if _is_push_selector(argument):
            print(
                f"{prog}: push selector option is not supported: {argument}",
                file=sys.stderr,
            )
            return 2

    status, bookmarks = _local_bookmarks()
    if status != 0:
        print(f"{prog}: failed to list bookmarks", file=sys.stderr)
        return 1
    if not bookmarks:
        return 0

    picker = _run(
        ["fzf", "--multi", "--prompt=Bookmarks to push> "],
        stdin="\n".join(bookmarks) + "\n",
    )
    if picker.returncode in {1, 130}:
        return 0
    if picker.returncode != 0:
        return picker.returncode
    selection = [line for line in picker.stdout.splitlines() if line]
    if not selection:
        return 0

    bookmark_arguments = [
        item
        for bookmark in selection
        for item in ("--bookmark", exact_string_pattern(bookmark))
    ]
    return run_status(
        ["jj", "git", "push", *arguments, *bookmark_arguments],
        error_type=InteractiveCommandError,
    )


def bookmark_rebase(arguments: Sequence[str], *, prog: str) -> int:
    """Select local bookmarks and rebase them onto one destination."""
    return _report_launch_error(
        lambda: _bookmark_rebase(arguments, prog=prog),
        prog=prog,
    )


def _bookmark_rebase(arguments: Sequence[str], *, prog: str) -> int:
    """Select local bookmarks and rebase them onto one destination."""
    parser = argparse.ArgumentParser(prog=prog)
    _ = parser.add_argument("destination", nargs="?", metavar="DESTINATION")
    namespace = parser.parse_args(arguments)

    status, bookmarks = _local_bookmarks()
    if status != 0:
        print(f"{prog}: failed to list bookmarks", file=sys.stderr)
        return 1
    if not bookmarks:
        return 0

    destination = cast("str | None", namespace.destination)
    candidates = bookmarks
    header = "Mark the bookmarks to rebase (Tab), then Enter"
    if destination is None:
        picker = _run(
            [
                "fzf",
                "--prompt=Destination> ",
                "--header=Step 1 of 2: choose the bookmark to rebase onto",
            ],
            stdin="\n".join(bookmarks) + "\n",
        )
        if picker.returncode in {1, 130}:
            return 0
        if picker.returncode != 0:
            return picker.returncode
        destination_bookmark = (
            picker.stdout.splitlines()[0] if picker.stdout.splitlines() else ""
        )
        if not destination_bookmark:
            return 0
        destination = bookmark_revset(destination_bookmark)
        candidates = [
            bookmark for bookmark in bookmarks if bookmark != destination_bookmark
        ]
        header = "Step 2 of 2: mark the bookmarks to rebase (Tab), then Enter"
    if not candidates:
        return 0

    picker = _run(
        [
            "fzf",
            "--multi",
            f"--prompt=Rebase onto {destination}> ",
            f"--header={header}",
        ],
        stdin="\n".join(candidates) + "\n",
    )
    if picker.returncode in {1, 130}:
        return 0
    if picker.returncode != 0:
        return picker.returncode
    selection = [line for line in picker.stdout.splitlines() if line]
    if not selection:
        return 0

    branches = [
        item
        for bookmark in selection
        for item in ("--branch", bookmark_revset(bookmark))
    ]
    return run_status(
        ["jj", "rebase", "--destination", destination, *branches],
        error_type=InteractiveCommandError,
    )


def bookmark_select(arguments: Sequence[str], *, prog: str) -> int:
    """Select and print one bookmark name."""
    return _report_launch_error(
        lambda: _bookmark_select(arguments, prog=prog),
        prog=prog,
    )


def _bookmark_select(arguments: Sequence[str], *, prog: str) -> int:
    """Select and print one bookmark name."""
    _ = argparse.ArgumentParser(prog=prog).parse_args(arguments)
    result = _run(
        [
            "jj",
            "log",
            "--no-graph",
            "-r",
            "bookmarks()",
            "-T",
            'coalesce(local_bookmarks) ++ "\\n"',
            "--color",
            "always",
        ]
    )
    if result.returncode != 0:
        print("bookmark-select command failed", file=sys.stderr)
        return 1
    if not result.stdout:
        return 0
    picker = _run(["fzf", "--ansi"], stdin=result.stdout)
    if picker.returncode in {1, 130}:
        return 0
    if picker.returncode != 0:
        return picker.returncode
    fields = picker.stdout.split()
    if fields:
        print(fields[0])
    return 0


def change_select(arguments: Sequence[str], *, prog: str) -> int:
    """Select and print one jj change ID."""
    return _report_launch_error(
        lambda: _change_select(arguments, prog=prog),
        prog=prog,
    )


def _change_select(arguments: Sequence[str], *, prog: str) -> int:
    """Select and print one jj change ID."""
    _ = argparse.ArgumentParser(prog=prog).parse_args(arguments)
    result = _run(
        [
            "jj",
            "log",
            "--no-graph",
            "-T",
            'change_id.shortest() ++ "\\t" ++ description.first_line() ++ " " ++ bookmarks.join("  ") ++ "\\n"',
            "--color",
            "always",
        ]
    )
    if result.returncode != 0:
        print("select command failed", file=sys.stderr)
        return 1
    if not result.stdout:
        return 0
    picker = _run(["fzf", "--ansi"], stdin=result.stdout)
    if picker.returncode in {1, 130}:
        return 0
    if picker.returncode != 0:
        return picker.returncode
    change_id = picker.stdout.partition("\t")[0].strip()
    if change_id:
        print(change_id)
    return 0
