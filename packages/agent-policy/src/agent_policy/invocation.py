"""Read a governed tool's argv: options, subcommand words, and operands.

Decisions are made on argv after shell parsing, never on a shell string.
Tokens after the first ``--`` are operands and never options. A token that
starts with ``-`` (other than ``-`` itself) is an option; one that does not is
a word. Value-taking options accept ``-X value``, ``-Xvalue``, ``-X=value``,
``--long value``, and ``--long=value``. A separate value token that starts with
``-`` is not consumed, so such a value needs the attached form; this keeps an
option from hiding behind another option's missing value.
"""

from __future__ import annotations

from collections.abc import Collection, Sequence
from dataclasses import dataclass
from enum import Enum

from .policy import GlobalOptionsPosition, OptionArity, OptionDeclaration, RuleScope, Tool


@dataclass(frozen=True)
class OptionOccurrence:
    """One option as written in argv.

    ``argv[start:end]`` holds its tokens: one, or two when the value is a
    separate token. ``declaration`` is ``None`` for an option the reader did
    not know; its ``spelling`` is then the token up to any ``=``.
    """

    spelling: str
    declaration: OptionDeclaration | None
    value: str | None
    start: int
    end: int
    is_global: bool


@dataclass(frozen=True)
class ParsedInvocation:
    """argv read against one rule's option declarations and the tool's globals.

    ``options`` lists every option before ``operands_start`` in argv order.
    """

    argv: tuple[str, ...]
    options: tuple[OptionOccurrence, ...]
    operands_start: int
    """Index of the first ``--`` in argv, or ``len(argv)`` without one."""

    def occurrences_of(self, declarations: Collection[OptionDeclaration]) -> list[OptionOccurrence]:
        """Return the occurrences of any of DECLARATIONS, in argv order."""
        return [option for option in self.options if option.declaration in declarations]


class ScopeMatch(Enum):
    """Whether a rule's scope covers an invocation."""

    COVERED = "covered"
    NOT_COVERED = "not-covered"
    UNDETERMINED = "undetermined"
    """An option the tool does not declare as global ended subcommand
    detection before the scope's path was seen, and the scope's remaining
    words still appear later in argv."""


@dataclass(frozen=True)
class SubcommandDetection:
    """The leading subcommand words of an invocation.

    Detection skips declared global options and their values where the tool
    allows them, and stops at ``--`` or at any other option.
    """

    words: tuple[str, ...]
    stopping_option_index: int | None
    """Index of the option that ended detection, or ``None`` when it ended
    at ``--`` or at the end of argv."""

    def match(self, scope: RuleScope, argv: Sequence[str]) -> ScopeMatch:
        """Decide whether SCOPE covers the invocation ARGV these words came from."""
        path = scope.subcommand_path
        if path is None or self.words[: len(path)] == path:
            return ScopeMatch.COVERED
        if self.stopping_option_index is None or self.words != path[: len(self.words)]:
            return ScopeMatch.NOT_COVERED

        remaining_path = iter(path[len(self.words) :])
        expected = next(remaining_path)
        for token in argv[self.stopping_option_index + 1 : operands_start(argv)]:
            if token == expected:
                next_word = next(remaining_path, None)
                if next_word is None:
                    return ScopeMatch.UNDETERMINED
                expected = next_word
        return ScopeMatch.NOT_COVERED


def detect_subcommand(tool: Tool, argv: Sequence[str]) -> SubcommandDetection:
    """Find the subcommand words of ARGV for TOOL."""
    words: list[str] = []
    end = operands_start(argv)
    index = 0
    while index < end:
        token = argv[index]
        if not is_option_token(token):
            words.append(token)
            index += 1
            continue

        global_option = (
            match_option(argv, index, tool.global_options, is_global=True)
            if accepts_global_options(tool, has_subcommand=bool(words))
            else None
        )
        if global_option is None:
            return SubcommandDetection(tuple(words), index)
        index = global_option.end
    return SubcommandDetection(tuple(words), None)


def parse_invocation(
    tool: Tool,
    argv: Sequence[str],
    declarations: Sequence[OptionDeclaration],
) -> ParsedInvocation:
    """Read every option of ARGV against TOOL's globals and DECLARATIONS.

    Global options are recognized where the tool accepts them and take
    precedence. Any other option token becomes an undeclared occurrence.
    """
    options: list[OptionOccurrence] = []
    has_subcommand = False
    end = operands_start(argv)
    index = 0
    while index < end:
        token = argv[index]
        if not is_option_token(token):
            has_subcommand = True
            index += 1
            continue

        option = None
        if accepts_global_options(tool, has_subcommand=has_subcommand):
            option = match_option(argv, index, tool.global_options, is_global=True)
        if option is None:
            option = match_option(argv, index, declarations, is_global=False)
        if option is None:
            option = OptionOccurrence(
                spelling=token.split("=", 1)[0],
                declaration=None,
                value=None,
                start=index,
                end=index + 1,
                is_global=False,
            )
        options.append(option)
        index = option.end
    return ParsedInvocation(argv=tuple(argv), options=tuple(options), operands_start=end)


def match_option(
    argv: Sequence[str],
    index: int,
    declarations: Sequence[OptionDeclaration],
    *,
    is_global: bool,
) -> OptionOccurrence | None:
    """Read the option at ARGV[INDEX] if it is one of DECLARATIONS.

    A flag written with an attached value (``--flag=x``) still matches, with
    that value, so callers can report it. A short flag followed by more
    characters (``-qv``) does not match: clusters are not read.
    """
    token = argv[index]
    for declaration in declarations:
        for name in declaration.names:
            if token == name:
                return _separate_value_occurrence(argv, index, name, declaration, is_global)

            is_short = not name.startswith("--")
            attached = token[len(name) :] if token.startswith(name) else None
            if attached is None or attached == "":
                continue
            if attached.startswith("="):
                value = attached[1:]
            elif is_short and declaration.arity is OptionArity.VALUE:
                value = attached
            else:
                continue
            return OptionOccurrence(
                spelling=name,
                declaration=declaration,
                value=value,
                start=index,
                end=index + 1,
                is_global=is_global,
            )
    return None


def _separate_value_occurrence(
    argv: Sequence[str],
    index: int,
    name: str,
    declaration: OptionDeclaration,
    is_global: bool,
) -> OptionOccurrence:
    """Read an option written alone, taking the next token as a needed value."""
    value = None
    end = index + 1
    if declaration.arity is OptionArity.VALUE and end < operands_start(argv):
        candidate = argv[end]
        if not is_option_token(candidate):
            value = candidate
            end += 1
    return OptionOccurrence(
        spelling=name,
        declaration=declaration,
        value=value,
        start=index,
        end=end,
        is_global=is_global,
    )


def accepts_global_options(tool: Tool, *, has_subcommand: bool) -> bool:
    """Report whether TOOL reads global options at a position after words."""
    return tool.global_options_position is GlobalOptionsPosition.ANYWHERE or not has_subcommand


def is_option_token(token: str) -> bool:
    """Report whether TOKEN is written as an option."""
    return token.startswith("-") and token != "-"


def operands_start(argv: Sequence[str]) -> int:
    """Return the index of the first ``--`` in ARGV, or its length."""
    try:
        return list(argv).index("--")
    except ValueError:
        return len(argv)
