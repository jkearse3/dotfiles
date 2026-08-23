"""Format or validate a commit description read from stdin.

The formatter is deliberately conservative: it rewrites only ordinary prose
paragraphs, list items, and trailers, and leaves line-sensitive content (code
fences, tables, diffs, other indented lines, URLs, inline code) byte-for-byte
intact, so formatted output may still fail validation. The one place that
conservatism yields is the line directly below a flush-left list item or
trailer: it is indistinguishable from a hand-wrapped continuation, so it is
absorbed into that value, and a blank line is what separates them. A `-` or
`+` marker is excepted, reading equally as a diff line, and takes only
indented continuations.

Line endings are normalized to LF and non-empty output ends with exactly one
newline. The validator intentionally does not enforce Conventional Commit
structure: any non-empty subject within the width limit is accepted.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from typing import cast

DEFAULT_BODY_WIDTH = 72
DEFAULT_SUBJECT_WIDTH = 72

# git folds a trailer's continuation line into the trailer value only when the
# line is indented; `git interpret-trailers --parse` drops an unindented one,
# silently truncating the value.
TRAILER_CONTINUATION_INDENT = "  "

LIST_RE = re.compile(r"^(?P<prefix>[ \t]*(?:[-+*]|\d+[.)])[ \t]+)(?P<text>\S.*)$")

# Only recognized Conventional Commits / git trailer keys count: hyphenated
# keys (Signed-off-by, Co-authored-by, BREAKING-CHANGE) or a known single-word
# key, matched case-insensitively because git accepts lowercase trailer keys.
# An arbitrary unhyphenated capitalized word before a colon ("Records: hold
# the state...") is ordinary prose and must wrap without hanging indent.
TRAILER_RE = re.compile(
    r"^(?P<prefix>(?:BREAKING CHANGE"
    + r"|(?i:[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+"
    + r"|Closes|Fixes|Resolves|Refs|Reverts|Cc|Link)):[ \t]+)(?P<text>\S.*)$"
)

# Issue-reference footers stay on their own lines: never joined into a
# paragraph and never wrapped.
ISSUE_REFERENCE_RE = re.compile(r"^(?:Closes #[0-9]+|Fixes [A-Z][A-Z0-9]*-[0-9]+)$")
DIFF_HEADER_RE = re.compile(
    r"^(?:(?:old|new|deleted file|new file) mode [0-7]{6}"
    + r"|(?:similarity|dissimilarity) index [0-9]+%"
    + r"|(?:rename|copy) (?:from|to) .+"
    + r"|index [0-9a-f]+\.\.[0-9a-f]+(?: [0-7]{6})?"
    + r"|(?:-{3}|\+{3}) \S.*"
    + r"|@@ -[0-9]+(?:,[0-9]+)? \+[0-9]+(?:,[0-9]+)? @@.*"
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


@dataclass
class Paragraph:
    """Lines that reflow together under one pair of line prefixes.

    Prose carries empty prefixes and reflows flush left. A list item or
    trailer keeps its marker as ``first_prefix`` and reflows its value
    under ``continuation_prefix`` as a hanging indent.
    """

    first_prefix: str
    continuation_prefix: str
    texts: list[str]


def open_paragraph(line: str) -> Paragraph | None:
    """Return the paragraph ``line`` opens, or ``None`` if it opens none.

    Blank, issue-reference, diff-header, and preformatted-looking lines
    open nothing, so they keep their existing line structure. A list item
    or trailer is matched ahead of that gate, so it opens a paragraph even
    when it looks preformatted. An indented line opens a paragraph only
    when it is a list item.
    """
    list_match = LIST_RE.fullmatch(line)
    if list_match is not None:
        prefix = list_match.group("prefix")
        return Paragraph(
            first_prefix=prefix,
            continuation_prefix=" " * len(prefix),
            texts=[list_match.group("text")],
        )

    trailer_match = TRAILER_RE.fullmatch(line)
    if trailer_match is not None:
        return Paragraph(
            first_prefix=trailer_match.group("prefix"),
            continuation_prefix=TRAILER_CONTINUATION_INDENT,
            texts=[trailer_match.group("text")],
        )

    if is_prose_line(line):
        return Paragraph(first_prefix="", continuation_prefix="", texts=[line])

    return None


def absorbs_flush_left_text(paragraph: Paragraph) -> bool:
    """Return whether ``paragraph`` may absorb an unindented soft-wrapped line.

    An indented paragraph takes only indented continuations, or a line
    below an indented code block would fold into it. A ``-`` or ``+``
    marker is ambiguous between a list bullet and a diff line, so it too
    continues only through an indented line; ``is_prose_continuation_line``
    gates prose on the same two characters.
    """
    marker = paragraph.first_prefix[:1]
    if not marker:
        return True

    return not marker.isspace() and marker not in "-+"


def paragraph_continuation_text(paragraph: Paragraph, line: str) -> str | None:
    """Return the text ``line`` adds to ``paragraph``, or ``None`` to end it.

    An unindented soft-wrapped line continues a flush-left paragraph, so a
    hand-wrapped list item or trailer reflows as one value instead of
    breaking into a fresh unindented paragraph. A line indented to
    exactly the hanging indent continues a list item or trailer;
    anything indented further is nested content that stays verbatim.
    """
    if absorbs_flush_left_text(paragraph) and is_prose_continuation_line(line):
        return line

    if not paragraph.continuation_prefix or not line.startswith(
        paragraph.continuation_prefix
    ):
        return None

    text = line[len(paragraph.continuation_prefix) :]
    return text if is_prose_continuation_line(text) else None


def render_paragraph(paragraph: Paragraph, *, width: int) -> list[str]:
    """Return ``paragraph`` as output lines.

    A paragraph the author already fit on one line passes through
    verbatim, so reflowing never collapses the internal spacing of an
    aligned list entry or a pasted diff line.
    """
    if len(paragraph.texts) == 1:
        single_line = paragraph.first_prefix + paragraph.texts[0]
        if len(single_line) <= width:
            return [single_line]

    return wrap_line(
        " ".join(paragraph.texts),
        width=width,
        first_prefix=paragraph.first_prefix,
        continuation_prefix=paragraph.continuation_prefix,
    )


def format_body_line(line: str, *, width: int) -> list[str]:
    """Return ``line`` reformatted to ``width`` as one or more lines.

    Only a line that opens no paragraph reaches this. Blank, indented,
    issue-reference, and preformatted-looking lines pass through
    verbatim. What remains is over-width prose that ``is_prose_line``
    rejects as an opener, such as a line starting with ``*`` or ``-``,
    and it wraps flush left.
    """
    if not line or len(line) <= width:
        return [line]

    if (
        line[0].isspace()
        or ISSUE_REFERENCE_RE.fullmatch(line) is not None
        or looks_preformatted(line)
    ):
        return [line]

    return wrap_line(line, width=width)


# Prose may also open with inline code, a parenthetical, or a quotation;
# other punctuation openers (diff markers, markup) stay line-sensitive.
PROSE_OPENER_PUNCTUATION = "`(\"'"


def is_prose_line(line: str) -> bool:
    """Return whether ``line`` may open a prose paragraph.

    The first-character gate excludes markup, indented content, and
    diff/patch lines, which must keep their existing line structure.
    """
    return bool(
        line
        and line[0].isascii()
        and (line[0].isalnum() or line[0] in PROSE_OPENER_PUNCTUATION)
        and is_prose_continuation_line(line)
    )


def is_prose_continuation_line(line: str) -> bool:
    """Return whether ``line`` may continue an open prose paragraph.

    Continuations are judged more permissively than openers because an
    author-inserted wrap point can land on any word: in-paragraph newlines
    are soft, and only blank, indented, or structural lines (lists,
    trailers, issue footers, diff lines, preformatted-looking content) end
    a paragraph. The ``-``/``+`` gate keeps bare patch lines out of prose;
    hunk and file headers before them are caught as preformatted.
    """
    return bool(
        line
        and not line[0].isspace()
        and line[0] not in "-+"
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
    masked out first so a URL or inline code containing ``|`` or ``--``
    does not trigger the rules. The mask is a word character rather than a
    space so that masking cannot itself fabricate structure: prose ending
    in a URL or inline code would otherwise read as a Markdown hard break
    and never reflow.
    """
    plain = line
    for start, end in reversed(unbreakable_spans(line)):
        plain = plain[:start] + "x" * (end - start) + plain[end:]

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

    The subject passes through unchanged. Body paragraphs reflow to
    ``body_width`` with in-paragraph newlines treated as soft: a paragraph
    ends only at a blank, fence, or structural line, so hand-wrapped text
    collapses to one logical line before wrapping. Prose reflows flush
    left; a list item or trailer reflows its value under a hanging indent,
    taking an unindented continuation unless its marker is ``-`` or ``+``.
    Fenced code, preformatted-looking
    lines, issue-reference footers, and other indented content pass through
    verbatim, so the result may still fail validation. Empty input stays
    empty; non-empty output ends with exactly one newline.
    """
    normalized = message.rstrip("\r\n")
    if not normalized:
        return ""

    lines = normalized.splitlines()
    result = [lines[0]]
    fence: str | None = None
    paragraph: Paragraph | None = None

    def flush_paragraph() -> None:
        nonlocal paragraph
        if paragraph is None:
            return

        result.extend(render_paragraph(paragraph, width=body_width))
        paragraph = None

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

        if paragraph is not None:
            continuation = paragraph_continuation_text(paragraph, line)
            if continuation is not None:
                paragraph.texts.append(continuation)
                continue

        flush_paragraph()

        paragraph = open_paragraph(line)
        if paragraph is None:
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
