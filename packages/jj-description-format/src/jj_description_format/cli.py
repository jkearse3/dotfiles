"""Reformat one jj revision's description through `commit-message`.

Reads the target revision's description, reformats it with
`commit-message format`, and gates the result behind `commit-message
validate`: an invalid formatted description aborts before any write. The
description is written back with `jj describe --stdin` only when the
formatted text is valid and differs from the current description, so an
already-clean description produces no jj operation. `--dry-run` prints a
unified diff of the would-be change and never writes.
"""

from __future__ import annotations

import argparse
import difflib
import os
import subprocess
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import cast


class DescriptionFormatError(Exception):
    """A concise, user-facing formatting failure."""


def positive_int(value: str) -> int:
    try:
        parsed = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be a positive integer") from error

    if parsed < 1:
        raise argparse.ArgumentTypeError("must be a positive integer")

    return parsed


def _run(
    command: Sequence[str],
    *,
    stdin: bytes | None = None,
    cwd: Path | None = None,
) -> subprocess.CompletedProcess[bytes]:
    """Run COMMAND and capture its output, raising only when it cannot start."""
    try:
        return subprocess.run(
            command,
            cwd=cwd,
            input=stdin,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except OSError as error:
        raise DescriptionFormatError(f"could not run {command[0]}: {error}") from error


def _run_ok(
    command: Sequence[str],
    *,
    stdin: bytes | None = None,
    cwd: Path | None = None,
) -> bytes:
    """Run COMMAND and return stdout, raising a user-facing error on failure."""
    result = _run(command, stdin=stdin, cwd=cwd)
    if result.returncode != 0:
        detail = os.fsdecode(result.stderr).strip()
        suffix = f": {detail}" if detail else ""
        raise DescriptionFormatError(f"{' '.join(command)} failed{suffix}")
    return result.stdout


def _read_description(revision: str, *, cwd: Path | None = None) -> str:
    """Return the description of the single revision matching REVISION.

    `jj describe` applies one message to every matched revision, so a revset
    matching more than one revision is rejected here before any write.
    """
    matches = os.fsdecode(
        _run_ok(
            [
                "jj",
                "--no-pager",
                "--color=never",
                "log",
                "--no-graph",
                "--ignore-working-copy",
                "-r",
                revision,
                "-T",
                'change_id ++ "\\n"',
            ],
            cwd=cwd,
        )
    ).splitlines()
    if not matches:
        raise DescriptionFormatError(f"revset matched no revisions: {revision}")
    if len(matches) > 1:
        raise DescriptionFormatError(
            f"revset must match exactly one revision, got {len(matches)}: {revision}"
        )

    return os.fsdecode(
        _run_ok(
            [
                "jj",
                "--no-pager",
                "--color=never",
                "log",
                "--no-graph",
                "--ignore-working-copy",
                "-r",
                revision,
                "-T",
                "description",
            ],
            cwd=cwd,
        )
    )


def _format(text: str, *, body_width: int | None) -> str:
    """Reformat TEXT through `commit-message format`."""
    command = ["commit-message", "format"]
    if body_width is not None:
        command.extend(["--body-width", str(body_width)])
    return os.fsdecode(_run_ok(command, stdin=text.encode()))


def _validate(
    text: str, *, subject_width: int | None, body_width: int | None
) -> None:
    """Gate TEXT behind `commit-message validate`, forwarding its diagnostics."""
    command = ["commit-message", "validate"]
    if subject_width is not None:
        command.extend(["--subject-width", str(subject_width)])
    if body_width is not None:
        command.extend(["--body-width", str(body_width)])
    result = _run(command, stdin=text.encode())
    if result.returncode != 0:
        _ = sys.stderr.write(os.fsdecode(result.stderr))
        raise DescriptionFormatError("formatted description failed validation")


def reformat(
    revision: str,
    *,
    dry_run: bool = False,
    subject_width: int | None = None,
    body_width: int | None = None,
    cwd: Path | None = None,
) -> int:
    """Reformat REVISION's description in place and return an exit status."""
    current = _read_description(revision, cwd=cwd)
    if not current.strip():
        raise DescriptionFormatError(f"revision has no description: {revision}")

    # `commit-message format` output ends with exactly one newline, so the
    # comparison normalizes the current description the same way and a clean
    # description is a true no-op rather than a churn write.
    normalized = current.rstrip("\r\n") + "\n"
    formatted = _format(normalized, body_width=body_width)
    _validate(formatted, subject_width=subject_width, body_width=body_width)

    if formatted == normalized:
        print("description already formatted")
        return 0

    if dry_run:
        _ = sys.stdout.writelines(
            difflib.unified_diff(
                normalized.splitlines(keepends=True),
                formatted.splitlines(keepends=True),
                fromfile="current",
                tofile="formatted",
            )
        )
        return 0

    _ = _run_ok(["jj", "describe", "-r", revision, "--stdin"], stdin=formatted.encode(), cwd=cwd)
    print(f"reformatted description of {revision}")
    return 0


def create_parser() -> argparse.ArgumentParser:
    """Create the command-line argument parser."""
    parser = argparse.ArgumentParser(
        prog="jj-description-format",
        description=(
            "Reformat a jj revision description through commit-message, writing it "
            "back only when the formatted result is valid and differs."
        ),
    )
    _ = parser.add_argument(
        "-r",
        "--revision",
        default="@",
        metavar="REVSET",
        help="revision whose description to reformat (default: @)",
    )
    _ = parser.add_argument(
        "--dry-run",
        action="store_true",
        help="show a unified diff of the would-be change without writing",
    )
    _ = parser.add_argument(
        "--subject-width",
        type=positive_int,
        metavar="N",
        help="maximum subject width forwarded to commit-message validate",
    )
    _ = parser.add_argument(
        "--body-width",
        type=positive_int,
        metavar="N",
        help="maximum body/footer line width forwarded to commit-message",
    )
    return parser


def main(arguments: Sequence[str] | None = None) -> int:
    """Run the command-line interface and return its exit status."""
    args = create_parser().parse_args(arguments)
    try:
        return reformat(
            cast(str, args.revision),
            dry_run=cast(bool, args.dry_run),
            subject_width=cast("int | None", args.subject_width),
            body_width=cast("int | None", args.body_width),
        )
    except DescriptionFormatError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
