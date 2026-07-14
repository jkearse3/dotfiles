#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from typing import cast

DEFAULT_BODY_WIDTH = 72
DEFAULT_SUBJECT_WIDTH = 72
URL_RE = re.compile(r"https?://\S+")
INLINE_CODE_RE = re.compile(r"`[^`\n]+`")


def validate_subject(
    subject: str,
    *,
    subject_width: int = DEFAULT_SUBJECT_WIDTH,
) -> list[str]:
    errors: list[str] = []

    if not subject:
        return ["line 1: subject is required"]

    if len(subject) > subject_width:
        errors.append(
            f"line 1: subject is {len(subject)} characters (max {subject_width})"
        )

    return errors


def validate_body_lines(lines: list[str], *, body_width: int) -> list[str]:
    errors: list[str] = []

    for line_number, line in enumerate(lines[1:], start=2):
        if not line.strip() or len(line) <= body_width:
            continue

        if has_allowed_unbreakable_overrun(line, body_width):
            continue

        errors.append(
            f"line {line_number}: body/footer line is {len(line)} characters "
            + f"(max {body_width})"
        )

    return errors


def has_allowed_unbreakable_overrun(line: str, width: int) -> bool:
    long_spans = [
        span for span in unbreakable_spans(line) if span[1] - span[0] > width
    ]
    if not long_spans:
        return False

    reduced_parts: list[str] = []
    start = 0
    for span_start, span_end in long_spans:
        reduced_parts.append(line[start:span_start])
        reduced_parts.append("x")
        start = span_end
    reduced_parts.append(line[start:])

    return len("".join(reduced_parts)) <= width


def unbreakable_spans(line: str) -> list[tuple[int, int]]:
    spans = [match.span() for match in URL_RE.finditer(line)]
    spans.extend(match.span() for match in INLINE_CODE_RE.finditer(line))
    spans.sort()

    merged: list[tuple[int, int]] = []
    for start, end in spans:
        if not merged or start >= merged[-1][1]:
            merged.append((start, end))
            continue

        merged[-1] = (merged[-1][0], max(merged[-1][1], end))

    return merged


def print_errors(errors: list[str]) -> None:
    print("commit message validation failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)


def positive_int(value: str) -> int:
    try:
        parsed = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be a positive integer") from error

    if parsed < 1:
        raise argparse.ArgumentTypeError("must be a positive integer")

    return parsed


@dataclass(frozen=True)
class Args:
    subject_width: int
    body_width: int


def parse_args(argv: list[str] | None = None) -> Args:
    parser = argparse.ArgumentParser(
        description="Validate a commit description read from stdin."
    )
    _ = parser.add_argument(
        "--subject-width",
        type=positive_int,
        default=DEFAULT_SUBJECT_WIDTH,
        help=f"maximum subject width in characters (default: {DEFAULT_SUBJECT_WIDTH})",
    )
    _ = parser.add_argument(
        "--body-width",
        type=positive_int,
        default=DEFAULT_BODY_WIDTH,
        help=(
            "maximum body/footer line width in characters "
            + f"(default: {DEFAULT_BODY_WIDTH})"
        ),
    )
    namespace = parser.parse_args(argv)
    return Args(
        subject_width=cast(int, namespace.subject_width),
        body_width=cast(int, namespace.body_width),
    )


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    message = sys.stdin.read()
    lines = message.splitlines()
    subject = lines[0] if lines else ""
    errors = validate_subject(
        subject,
        subject_width=args.subject_width,
    )
    errors.extend(validate_body_lines(lines, body_width=args.body_width))

    if errors:
        print_errors(errors)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
