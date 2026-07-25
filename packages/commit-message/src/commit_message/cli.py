from __future__ import annotations

import argparse
import re
import sys
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
LIST_RE = re.compile(r"^(?P<prefix>[ \t]*(?:[-+*]|\d+[.)])[ \t]+)(?P<text>\S.*)$")
TRAILER_RE = re.compile(
    r"^(?P<prefix>(?:BREAKING CHANGE|[A-Za-z0-9-]+):[ \t]+)(?P<text>\S.*)$"
)
FOOTER_RE = re.compile(r"^(?:Closes #[0-9]+|Fixes [A-Z][A-Z0-9]*-[0-9]+)$")
DIFF_HEADER_RE = re.compile(
    r"^(?:(?:old|new|deleted file|new file) mode [0-7]{6}"
    + r"|(?:similarity|dissimilarity) index [0-9]+%"
    + r"|(?:rename|copy) (?:from|to) .+"
    + r"|index [0-9a-f]+\.\.[0-9a-f]+(?: [0-7]{6})?"
    + r"|Binary files .+ differ)$"
)
URL_RE = re.compile(r"https?://\S+")
INLINE_CODE_RE = re.compile(r"`[^`\n]+`")
FENCE_RE = re.compile(r"^[ \t]*(?P<marker>`{3,}|~{3,})")


def positive_int(value: str) -> int:
    try:
        parsed = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be a positive integer") from error

    if parsed < 1:
        raise argparse.ArgumentTypeError("must be a positive integer")

    return parsed


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


def words(text: str) -> list[str]:
    spans = iter(unbreakable_spans(text))
    span = next(spans, None)
    result: list[str] = []
    position = 0

    while position < len(text):
        while position < len(text) and text[position].isspace():
            position += 1
        if position == len(text):
            break

        start = position
        while position < len(text):
            if span is not None and position == span[0]:
                position = span[1]
                span = next(spans, None)
                continue
            if text[position].isspace():
                break
            position += 1
        result.append(text[start:position])

    return result


def wrap_line(
    text: str,
    *,
    width: int,
    first_prefix: str = "",
    continuation_prefix: str = "",
) -> list[str]:
    tokens = words(text)
    if not tokens:
        return [first_prefix.rstrip()]

    lines: list[str] = []
    current = first_prefix
    for token in tokens:
        separator = "" if current == first_prefix else " "
        if current != first_prefix and len(current) + 1 + len(token) > width:
            lines.append(current)
            current = continuation_prefix + token
            continue
        current += separator + token
    lines.append(current)
    return lines


def format_subject(subject: str) -> str:
    if len(subject) > DEFAULT_SUBJECT_WIDTH:
        return subject

    match = SUBJECT_RE.fullmatch(subject)
    if match is None or match.group("type") not in DEFAULT_TYPES:
        return subject

    description = match.group("description")
    if (
        re.match(r"[a-z]", description[0]) is None
        or not description.endswith(".")
        or description.endswith("..")
    ):
        return subject

    return subject[:-1]


def format_body_line(line: str, *, width: int) -> list[str]:
    if not line or len(line) <= width or FOOTER_RE.fullmatch(line) is not None:
        return [line]

    list_match = LIST_RE.fullmatch(line)
    if list_match is not None:
        prefix = list_match.group("prefix")
        return wrap_line(
            list_match.group("text"),
            width=width,
            first_prefix=prefix,
            continuation_prefix=" " * len(prefix),
        )

    trailer_match = TRAILER_RE.fullmatch(line)
    if trailer_match is not None:
        return wrap_line(
            trailer_match.group("text"),
            width=width,
            first_prefix=trailer_match.group("prefix"),
            continuation_prefix="  ",
        )

    if line[0].isspace() or looks_preformatted(line):
        return [line]

    return wrap_line(line, width=width)


def is_prose_line(line: str) -> bool:
    return bool(
        line
        and line[0].isascii()
        and line[0].isalnum()
        and LIST_RE.fullmatch(line) is None
        and TRAILER_RE.fullmatch(line) is None
        and FOOTER_RE.fullmatch(line) is None
        and not looks_preformatted(line)
    )


def looks_preformatted(line: str) -> bool:
    plain = line
    for start, end in reversed(unbreakable_spans(line)):
        plain = plain[:start] + " " * (end - start) + plain[end:]

    return (
        plain.startswith(("```", "~~~", ">", "|", "#", "$ ", "./"))
        or "\t" in plain
        or " --" in plain
        or " | " in plain
        or " && " in plain
        or " || " in plain
        or plain.endswith(" \\")
        or plain.endswith("  ")
        or plain[0] in "{["
        or re.fullmatch(r"(?:={3,}|-{3,}|\*{3,})", plain) is not None
        or DIFF_HEADER_RE.fullmatch(plain) is not None
    )


def format_message(message: str, *, body_width: int) -> str:
    normalized = message.rstrip("\r\n")
    if not normalized:
        return ""

    lines = normalized.splitlines()
    result = [format_subject(lines[0])]
    fence: str | None = None
    paragraph: list[str] = []

    def flush_paragraph() -> None:
        if paragraph:
            result.extend(wrap_line(" ".join(paragraph), width=body_width))
            paragraph.clear()

    for line in lines[1:]:
        fence_match = FENCE_RE.match(line)
        if fence is not None:
            result.append(line)
            closing_marker = line.strip()
            if len(closing_marker) >= len(fence) and set(closing_marker) == {fence[0]}:
                fence = None
            continue
        if fence_match is not None:
            flush_paragraph()
            fence = fence_match.group("marker")
            result.append(line)
            continue
        if is_prose_line(line):
            paragraph.append(line)
            continue
        flush_paragraph()
        result.extend(format_body_line(line, width=body_width))
    flush_paragraph()
    return "\n".join(result) + "\n"


def validate_subject(
    subject: str,
    *,
    subject_width: int = DEFAULT_SUBJECT_WIDTH,
) -> list[str]:
    if not subject:
        return ["line 1: subject is required"]
    if len(subject) > subject_width:
        return [f"line 1: subject is {len(subject)} characters (max {subject_width})"]
    return []


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
    long_spans = [span for span in unbreakable_spans(line) if span[1] - span[0] > width]
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


def print_errors(errors: list[str]) -> None:
    print("commit message validation failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="commit-message",
        description="Format or validate a commit description read from stdin.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    formatter = subparsers.add_parser(
        "format", description="Mechanically format a commit description read from stdin."
    )
    _ = formatter.add_argument(
        "--body-width",
        type=positive_int,
        default=DEFAULT_BODY_WIDTH,
        help=(
            "maximum body/footer line width in characters "
            + f"(default: {DEFAULT_BODY_WIDTH})"
        ),
    )

    checker = subparsers.add_parser(
        "check", description="Validate a commit description read from stdin."
    )
    _ = checker.add_argument(
        "--subject-width",
        type=positive_int,
        default=DEFAULT_SUBJECT_WIDTH,
        help=f"maximum subject width in characters (default: {DEFAULT_SUBJECT_WIDTH})",
    )
    _ = checker.add_argument(
        "--body-width",
        type=positive_int,
        default=DEFAULT_BODY_WIDTH,
        help=(
            "maximum body/footer line width in characters "
            + f"(default: {DEFAULT_BODY_WIDTH})"
        ),
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    namespace = create_parser().parse_args(argv)
    message = sys.stdin.read()
    if cast(str, namespace.command) == "format":
        _ = sys.stdout.write(
            format_message(message, body_width=cast(int, namespace.body_width))
        )
        return 0

    lines = message.splitlines()
    subject = lines[0] if lines else ""
    errors = validate_subject(subject, subject_width=cast(int, namespace.subject_width))
    errors.extend(validate_body_lines(lines, body_width=cast(int, namespace.body_width)))
    if errors:
        print_errors(errors)
        return 1
    return 0
