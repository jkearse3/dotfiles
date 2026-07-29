"""Format or validate a commit description read from stdin.

The formatter is deliberately conservative: it rewrites only ordinary prose
paragraphs, list items, and trailers, and leaves line-sensitive content (code
fences, tables, diffs, other indented lines, URLs, inline code) byte-for-byte
intact, so formatted output may still fail validation. Line endings are
normalized to LF and non-empty output ends with exactly one newline. The
validator intentionally does not enforce Conventional Commit structure: any
non-empty subject within the width limit is accepted.
"""

from __future__ import annotations

import argparse
import re
import sys
from typing import cast

DEFAULT_BODY_WIDTH = 72
DEFAULT_SUBJECT_WIDTH = 72

LIST_RE = re.compile(r"^(?P<prefix>[ \t]*(?:[-+*]|\d+[.)])[ \t]+)(?P<text>\S.*)$")
TRAILER_RE = re.compile(
    r"^(?P<prefix>(?:BREAKING CHANGE|[A-Za-z0-9-]+):[ \t]+)(?P<text>\S.*)$"
)

# Issue-reference footers stay on their own lines: never joined into a
# paragraph and never wrapped.
ISSUE_REFERENCE_RE = re.compile(r"^(?:Closes #[0-9]+|Fixes [A-Z][A-Z0-9]*-[0-9]+)$")
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
    """Return the ordered, disjoint spans of ``line`` that must never split.

    URLs and inline code stop working when broken across lines, so wrapping
    and width validation treat each span as atomic. Overlapping matches are
    merged into one span.
    """
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


def split_unbreakable_words(text: str) -> list[str]:
    """Split ``text`` into whitespace-separated words.

    Each unbreakable span stays intact as a single word even where it
    contains no whitespace, so wrapping never divides it.
    """
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
    """Wrap ``text`` to ``width`` with first- and continuation-line prefixes.

    Words are never split, so an unbreakable word may leave a line over
    ``width``; validation tolerates exactly that overrun.
    """
    words = split_unbreakable_words(text)
    if not words:
        return [first_prefix.rstrip()]

    lines: list[str] = []
    current = first_prefix
    for word in words:
        separator = "" if current == first_prefix else " "
        if current != first_prefix and len(current) + 1 + len(word) > width:
            lines.append(current)
            current = continuation_prefix + word
            continue
        current += separator + word
    lines.append(current)
    return lines


def format_body_line(line: str, *, width: int) -> list[str]:
    """Return ``line`` reformatted to ``width`` as one or more lines.

    List items and trailers wrap with continuation indentation.
    Issue-reference footers, other indented lines, and
    preformatted-looking lines pass through verbatim; anything else wraps
    as plain prose.
    """
    if not line or len(line) <= width or ISSUE_REFERENCE_RE.fullmatch(line) is not None:
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
    """Return whether ``line`` is ordinary prose that may join a paragraph.

    The ASCII-alnum first-character gate excludes markup, indented content,
    and continuation lines, which must keep their existing line structure.
    """
    return bool(
        line
        and line[0].isascii()
        and line[0].isalnum()
        and LIST_RE.fullmatch(line) is None
        and TRAILER_RE.fullmatch(line) is None
        and ISSUE_REFERENCE_RE.fullmatch(line) is None
        and not looks_preformatted(line)
    )


def looks_preformatted(line: str) -> bool:
    """Return whether ``line`` looks line-sensitive and must not be reflowed.

    This is a heuristic and false positives are intentional: misclassifying
    prose as preformatted merely leaves it untouched, while the reverse
    corrupts quoted commands, tables, and diffs. Unbreakable spans are
    blanked out first so a URL or inline code containing ``|`` or ``--``
    does not trigger the rules.
    """
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
    """Mechanically format a commit description.

    The subject passes through unchanged. Body prose paragraphs reflow to
    ``body_width``, and list items and trailers wrap with continuation
    indentation. Fenced code, preformatted-looking lines, issue-reference
    footers, and other indented content pass through verbatim, so the result
    may still fail validation. Empty input stays empty; non-empty output ends
    with exactly one newline.
    """
    normalized = message.rstrip("\r\n")
    if not normalized:
        return ""

    lines = normalized.splitlines()
    result = [lines[0]]
    fence: str | None = None
    paragraph: list[str] = []

    def flush_paragraph() -> None:
        if paragraph:
            result.extend(wrap_line(" ".join(paragraph), width=body_width))
            paragraph.clear()

    for line in lines[1:]:
        if fence is not None:
            result.append(line)
            closing_marker = line.strip()
            # A closing fence is a run of the opening fence character at
            # least as long as the opening fence.
            if len(closing_marker) >= len(fence) and set(closing_marker) == {fence[0]}:
                fence = None
            continue

        fence_match = FENCE_RE.match(line)
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


def validate_subject(subject: str, *, subject_width: int) -> list[str]:
    """Return subject line errors; only presence and width are validated."""
    if not subject:
        return ["line 1: subject is required"]
    if len(subject) > subject_width:
        return [f"line 1: subject is {len(subject)} characters (max {subject_width})"]
    return []


def validate_body_lines(lines: list[str], *, body_width: int) -> list[str]:
    """Return width errors for body/footer lines.

    Blank lines pass, as do lines whose overrun comes solely from
    unbreakable spans.
    """
    errors: list[str] = []
    for line_number, line in enumerate(lines[1:], start=2):
        if not line.strip() or len(line) <= body_width:
            continue
        if has_allowed_unbreakable_overrun(line, body_width=body_width):
            continue
        errors.append(
            f"line {line_number}: body/footer line is {len(line)} characters "
            + f"(max {body_width})"
        )
    return errors


def has_allowed_unbreakable_overrun(line: str, *, body_width: int) -> bool:
    """Return whether ``line`` exceeds ``body_width`` only via unbreakable spans.

    A URL or inline-code span too long to wrap cannot be split, so a line is
    acceptable when its remaining text fits once each overlong span is
    collapsed to a single character.
    """
    long_spans = [
        span for span in unbreakable_spans(line) if span[1] - span[0] > body_width
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
    return len("".join(reduced_parts)) <= body_width


def print_validation_errors(errors: list[str]) -> None:
    print("commit description validation failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)


def create_parser() -> argparse.ArgumentParser:
    """Build the command-line parser for the format and validate subcommands."""
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

    validator = subparsers.add_parser(
        "validate", description="Validate a commit description read from stdin."
    )
    _ = validator.add_argument(
        "--subject-width",
        type=positive_int,
        default=DEFAULT_SUBJECT_WIDTH,
        help=f"maximum subject width in characters (default: {DEFAULT_SUBJECT_WIDTH})",
    )
    _ = validator.add_argument(
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
    """Run the CLI: format or validate a commit description read from stdin."""
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
        print_validation_errors(errors)
        return 1
    return 0
