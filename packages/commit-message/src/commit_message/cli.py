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
subject structure: any non-empty subject within the width limit is accepted,
while recognized footer metadata must use canonical structure.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from typing import Literal, cast

DEFAULT_BODY_WIDTH = 72
DEFAULT_SUBJECT_WIDTH = 72

# Git folds a trailer's continuation line into the trailer value only when the
# line is indented; `git interpret-trailers --parse` drops an unindented one,
# silently truncating the value. Conventional Commits' space-containing
# `BREAKING CHANGE` token is not a Git trailer and therefore wraps as prose.
TRAILER_CONTINUATION_INDENT = "  "
BREAKING_CHANGE_PREFIX = "BREAKING CHANGE:"

LIST_RE = re.compile(r"^(?P<prefix>[ \t]*(?:[-+*]|\d+[.)])[ \t]+)(?P<text>\S.*)$")

# Only recognized Conventional Commits / git trailer keys count: hyphenated
# keys (Signed-off-by, Co-authored-by, BREAKING-CHANGE) or a known single-word
# key, matched case-insensitively because git accepts lowercase trailer keys.
# An arbitrary unhyphenated capitalized word before a colon ("Records: hold
# the state...") is ordinary prose and must wrap without hanging indent.
TRAILER_RE = re.compile(
    r"^(?P<prefix>(?:BREAKING CHANGE"
    + r"|(?i:[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+"
    + r"|Reverts|Cc|Link)):[ \t]+)(?P<text>\S.*)$"
)

# Issue-reference footers stay on their own lines: never joined into a
# paragraph and never wrapped. Their canonical form uses one tracker identifier
# per line and no terminal punctuation. A broader candidate expression keeps
# malformed references structurally intact so validation can report them after
# formatting instead of allowing them to merge into adjacent prose.
ISSUE_REFERENCE_KEYWORD = r"(?:Closes|Fixes|Resolves|Refs)"
GITHUB_OWNER = r"[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?"
GITHUB_REPOSITORY = r"(?!(?:\.{1,2})#)[A-Za-z0-9_.-]+"
ISSUE_REFERENCE_ID = (
    rf"(?:#[0-9]+|{GITHUB_OWNER}/{GITHUB_REPOSITORY}#[0-9]+"
    + r"|[A-Z][A-Z0-9]*-[0-9]+)"
)
ISSUE_REFERENCE_RE = re.compile(rf"^{ISSUE_REFERENCE_KEYWORD} {ISSUE_REFERENCE_ID}$")
ISSUE_REFERENCE_CANDIDATE_RE = re.compile(
    r"^(?i:Closes|Fixes|Resolves|Refs)(?:[ \t]|:|$)"
)

# Validation accepts the same intentionally bounded trailer vocabulary that the
# formatter can preserve and wrap unambiguously. Arbitrary single-word prefixes
# such as `Records:` remain prose; standard hyphenated Git tokens and the known
# single-word tokens below are trailers.
CANONICAL_TRAILER_RE = re.compile(
    r"^(?P<token>BREAKING CHANGE"
    + r"|(?i:[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+|Reverts|Cc|Link))"
    + r": (?P<text>\S.*)$"
)
TRAILER_CANDIDATE_RE = re.compile(
    r"^(?:BREAKING CHANGE"
    + r"|(?i:[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+|Reverts|Cc|Link))"
    + r"[ \t]*:"
)
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
        prefix = trailer_match.group("prefix")
        continuation_prefix = (
            "" if prefix.startswith(BREAKING_CHANGE_PREFIX) else TRAILER_CONTINUATION_INDENT
        )
        return Paragraph(
            first_prefix=prefix,
            continuation_prefix=continuation_prefix,
            texts=[trailer_match.group("text")],
        )

    if (
        ISSUE_REFERENCE_CANDIDATE_RE.match(line) is not None
        or TRAILER_CANDIDATE_RE.match(line) is not None
    ):
        return None
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
        or ISSUE_REFERENCE_CANDIDATE_RE.match(line) is not None
        or TRAILER_CANDIDATE_RE.match(line) is not None
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


def is_diff_marker_line(line: str) -> bool:
    """Return whether ``line`` begins with a single unified-diff +/- marker.

    A diff added or removed line starts with exactly one ``+`` or ``-``; a
    ``--``/``++`` prefix is a long-option token in prose (``--mime``), not a
    marker, and diff file headers (``--- ``/``+++ ``) are recognized as
    preformatted instead. Keeping long-option lines out of this gate lets
    prose about CLI flags reflow rather than fragmenting at each flag.
    """
    return bool(line) and line[0] in "-+" and (len(line) < 2 or line[1] not in "-+")


def is_prose_continuation_line(line: str) -> bool:
    """Return whether ``line`` may continue an open prose paragraph.

    Continuations are judged more permissively than openers because an
    author-inserted wrap point can land on any word: in-paragraph newlines
    are soft, and only blank, indented, or structural lines (lists,
    trailers, issue footers, diff lines, preformatted-looking content) end
    a paragraph. The single-``-``/``+`` gate keeps bare patch lines out of
    prose; hunk and file headers before them are caught as preformatted.
    """
    return bool(
        line
        and not line[0].isspace()
        and not is_diff_marker_line(line)
        and LIST_RE.fullmatch(line) is None
        and TRAILER_RE.fullmatch(line) is None
        and ISSUE_REFERENCE_CANDIDATE_RE.match(line) is None
        and TRAILER_CANDIDATE_RE.match(line) is None
        and not looks_preformatted(line)
    )


def looks_preformatted(line: str) -> bool:
    """Return whether ``line`` looks line-sensitive and must not be reflowed.

    This is a heuristic and false positives are intentional: misclassifying
    prose as preformatted merely leaves it untouched, while the reverse
    corrupts quoted commands, tables, and diffs. Unbreakable spans are
    masked out first so a URL or inline code containing ``|`` does not
    trigger the rules. The mask is a word character rather than a space so
    that masking cannot itself fabricate structure: prose ending in a URL
    or inline code would otherwise read as a Markdown hard break and never
    reflow.

    Inline command and code operators are deliberately not treated as
    preformatted: commit prose routinely names CLI flags (``--mime``) and
    quotes code (``file.type || 'default'``, ``a && b``) without fencing,
    and letting a ``--``, ``&&``, or ``||`` end a paragraph fragmented
    reflowed text. Genuine command lines stay verbatim when fenced,
    indented, or ``$ ``/``./`` prefixed, which the remaining rules catch.
    """
    plain = line
    for start, end in reversed(unbreakable_spans(line)):
        plain = plain[:start] + "x" * (end - start) + plain[end:]

    return (
        plain.startswith(("```", "~~~", ">", "|", "#", "$ ", "./"))
        or "\t" in plain
        or " | " in plain
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
    collapses to one logical line before wrapping. Prose and ``BREAKING
    CHANGE`` values reflow flush left; a list item or Git trailer reflows its
    value under a hanging indent, taking an unindented continuation unless its
    marker is ``-`` or ``+``. Fenced code, preformatted-looking lines,
    issue-reference footers, and other indented content pass through
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


def footer_candidate_indices(lines: list[str]) -> list[int]:
    """Return body-line indices that may begin footer metadata.

    Fenced examples are excluded because their contents are line-sensitive sample
    text, not commit metadata.
    """
    indices: list[int] = []
    fence: str | None = None
    for index, line in enumerate(lines[1:], start=1):
        if fence is not None:
            closing_marker = line.strip()
            if (
                len(closing_marker) >= len(fence)
                and set(closing_marker) == {fence[0]}
            ):
                fence = None
            continue

        fence_match = FENCE_RE.match(line)
        if fence_match is not None:
            fence = fence_match.group("marker")
            continue

        if (
            ISSUE_REFERENCE_CANDIDATE_RE.match(line) is not None
            or TRAILER_CANDIDATE_RE.match(line) is not None
        ):
            indices.append(index)

    return indices


def validate_footer_lines(lines: list[str], *, required_footers: list[str]) -> list[str]:
    """Return structural footer errors and missing required-footer errors.

    Recognized issue references and trailers form one final, contiguous block
    separated from the body by a blank line. Issue-reference keywords are
    reserved, so malformed variants remain detectable rather than becoming prose.
    """
    errors: list[str] = []
    if len(lines) < 2:
        return [f"required footer is missing: {footer}" for footer in required_footers]

    final_line_index = len(lines) - 1
    while final_line_index > 0 and not lines[final_line_index].strip():
        final_line_index -= 1

    final_block_start = final_line_index
    while final_block_start > 0 and lines[final_block_start - 1].strip():
        final_block_start -= 1

    candidate_indices = footer_candidate_indices(lines)
    final_candidates = [
        index
        for index in candidate_indices
        if final_block_start <= index <= final_line_index
    ]

    for index in candidate_indices:
        if index < final_block_start:
            errors.append(
                f"line {index + 1}: footer entry must be in the final footer block"
            )

    footer_entries: list[str] = []
    if final_candidates:
        footer_start = final_candidates[0]
        if footer_start != final_block_start or footer_start == 1:
            errors.append(
                f"line {footer_start + 1}: footer block must be separated "
                + "from the body by a blank line"
            )

        continuation_style: Literal["breaking", "indented"] | None = None
        footer_fence: str | None = None
        for index in range(footer_start, final_line_index + 1):
            line = lines[index]
            if footer_fence is not None:
                closing_marker = line.strip()
                if (
                    len(closing_marker) >= len(footer_fence)
                    and set(closing_marker) == {footer_fence[0]}
                ):
                    footer_fence = None
                continue

            fence_match = FENCE_RE.match(line)
            if continuation_style == "breaking" and fence_match is not None:
                footer_fence = fence_match.group("marker")
                continue

            issue_match = ISSUE_REFERENCE_RE.fullmatch(line)
            trailer_match = CANONICAL_TRAILER_RE.fullmatch(line)

            if issue_match is not None:
                footer_entries.append(line)
                continuation_style = None
                continue

            if trailer_match is not None:
                footer_entries.append(line)
                continuation_style = (
                    "breaking"
                    if trailer_match.group("token") == "BREAKING CHANGE"
                    else "indented"
                )
                continue

            if ISSUE_REFERENCE_CANDIDATE_RE.match(line) is not None:
                errors.append(
                    f"line {index + 1}: malformed issue-reference footer; "
                    + "use one unpunctuated identifier after the keyword"
                )
                continuation_style = None
                continue

            if TRAILER_CANDIDATE_RE.match(line) is not None:
                errors.append(
                    f"line {index + 1}: malformed trailer; use `Token: value`"
                )
                continuation_style = "indented"
                continue

            if line[:1].isspace() and line.strip():
                if continuation_style is None:
                    errors.append(
                        f"line {index + 1}: footer continuation has no preceding trailer"
                    )
                continue

            if continuation_style == "breaking":
                continue

            errors.append(f"line {index + 1}: footer block contains a non-footer line")
            continuation_style = None

    for footer in required_footers:
        if (
            ISSUE_REFERENCE_RE.fullmatch(footer) is None
            and CANONICAL_TRAILER_RE.fullmatch(footer) is None
        ):
            errors.append(f"required footer is not canonical: {footer}")
        elif footer not in footer_entries:
            errors.append(f"required footer is missing: {footer}")

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
    _ = validator.add_argument(
        "--require-footer",
        action="append",
        default=[],
        help="require an exact canonical footer (repeatable)",
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
    errors.extend(
        validate_footer_lines(
            lines,
            required_footers=cast(list[str], namespace.require_footer),
        )
    )

    if errors:
        print_validation_errors(errors)
        return 1
    return 0
