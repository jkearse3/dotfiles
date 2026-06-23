#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from typing import cast

DEFAULT_BODY_WIDTH = 72
DEFAULT_SUBJECT_WIDTH = 72
DEFAULT_TYPES = (
    "feat",
    "fix",
    "refactor",
    "perf",
    "style",
    "chore",
    "docs",
    "test",
    "ci",
    "build",
)
SUBJECT_RE = re.compile(
    r"^(?P<type>[a-z]+)(?:\((?P<scope>[^()\n]+)\))?(?P<breaking>!)?: "
    + r"(?P<description>.+)$"
)
URL_RE = re.compile(r"https?://\S+")
INLINE_CODE_RE = re.compile(r"`[^`\n]+`")


def validate_subject(
    subject: str,
    *,
    subject_width: int = DEFAULT_SUBJECT_WIDTH,
    allowed_types: tuple[str, ...] = DEFAULT_TYPES,
) -> list[str]:
    errors: list[str] = []

    if not subject:
        return ["line 1: subject is required"]

    if len(subject) > subject_width:
        errors.append(
            f"line 1: subject is {len(subject)} characters (max {subject_width})"
        )

    match = SUBJECT_RE.match(subject)
    if match is None:
        errors.append(
            "line 1: subject must match "
            + "'<type>(<scope>)?: <description>' with optional '!' before ':'"
        )
        return errors

    commit_type = match.group("type")
    description = match.group("description")

    if commit_type not in allowed_types:
        errors.append(
            "line 1: type must be one of " + ", ".join(sorted(allowed_types))
        )

    if not re.match(r"[a-z]", description[0]):
        errors.append("line 1: description must start with a lowercase letter")

    if description.endswith("."):
        errors.append("line 1: description must not end with a period")

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


def parse_types(value: str) -> tuple[str, ...]:
    types = tuple(item.strip() for item in value.split(",") if item.strip())
    if not types:
        raise argparse.ArgumentTypeError("must include at least one type")

    invalid = [item for item in types if not re.fullmatch(r"[a-z]+", item)]
    if invalid:
        raise argparse.ArgumentTypeError(
            "types must be lowercase ASCII words: " + ", ".join(invalid)
        )

    return types


@dataclass(frozen=True)
class Args:
    subject_width: int
    body_width: int
    types: tuple[str, ...]


def parse_args(argv: list[str] | None = None) -> Args:
    parser = argparse.ArgumentParser(
        description="Validate a Conventional Commit description read from stdin."
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
    _ = parser.add_argument(
        "--types",
        type=parse_types,
        default=DEFAULT_TYPES,
        help="comma-separated allowed Conventional Commit types",
    )
    namespace = parser.parse_args(argv)
    return Args(
        subject_width=cast(int, namespace.subject_width),
        body_width=cast(int, namespace.body_width),
        types=cast(tuple[str, ...], namespace.types),
    )


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    message = sys.stdin.read()
    lines = message.splitlines()
    subject = lines[0] if lines else ""
    errors = validate_subject(
        subject,
        subject_width=args.subject_width,
        allowed_types=args.types,
    )
    errors.extend(validate_body_lines(lines, body_width=args.body_width))

    if errors:
        print_errors(errors)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
