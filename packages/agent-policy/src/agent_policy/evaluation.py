"""Evaluate a tool's rules against one invocation and apply user approval.

Rules are evaluated independently and every refusal is reported. An allowlist
leaves options that an in-scope ``refuse-option`` rule of the same tool lists
to that rule, so one option is never refused twice. A rule whose ID the user
approved through ``AGENT_POLICY_APPROVE`` is skipped entirely, including its
named checks.
"""

from __future__ import annotations

import re
from collections.abc import Mapping, Sequence
from dataclasses import dataclass

from .checks import NAMED_CHECKS, CheckRequest
from .invocation import (
    OptionOccurrence,
    ParsedInvocation,
    ScopeMatch,
    SubcommandDetection,
    detect_subcommand,
    match_option,
    operands_start,
    parse_invocation,
)
from .policy import (
    AllowlistRule,
    OptionArity,
    RefuseOptionRule,
    RefuseSubcommandRule,
    Rule,
    RuleScope,
    Tool,
    ValueConstraint,
)

APPROVAL_VARIABLE = "AGENT_POLICY_APPROVE"
"""Environment variable listing, comma-separated, the rule IDs the user
approved for one command. Unset or empty approves nothing; only exact rule
IDs count, so values such as ``1`` approve nothing."""


@dataclass(frozen=True)
class Refusal:
    """A rule's objection to an invocation, with every reason it found."""

    rule: Rule
    reasons: tuple[str, ...]
    """Clauses without final periods, such as ``it runs `git push```."""


def evaluate(tool: Tool, argv: Sequence[str], environment: Mapping[str, str]) -> list[Refusal]:
    """Return the refusals of TOOL's rules for ARGV that the user did not approve.

    ENVIRONMENT is the invocation's process environment; its
    ``AGENT_POLICY_APPROVE`` selects approved rules, and named checks see it
    without that variable. An empty result means the invocation may run.
    """
    approved = approved_rule_ids(environment.get(APPROVAL_VARIABLE))
    context = _EvaluationContext(
        tool=tool,
        argv=tuple(argv),
        detection=detect_subcommand(tool, argv),
        check_environment=without_approval(environment),
    )

    refusals: list[Refusal] = []
    for rule in tool.rules:
        if rule.id in approved:
            continue
        reasons = _rule_reasons(context, rule)
        if len(reasons) > 0:
            refusals.append(Refusal(rule, tuple(reasons)))
    return refusals


def approved_rule_ids(value: str | None) -> frozenset[str]:
    """Parse an ``AGENT_POLICY_APPROVE`` VALUE into the approved rule IDs."""
    if value is None:
        return frozenset()
    return frozenset(item.strip() for item in value.split(",") if item.strip() != "")


def without_approval(environment: Mapping[str, str]) -> dict[str, str]:
    """Return a copy of ENVIRONMENT without ``AGENT_POLICY_APPROVE``."""
    return {name: value for name, value in environment.items() if name != APPROVAL_VARIABLE}


@dataclass(frozen=True)
class _EvaluationContext:
    tool: Tool
    argv: tuple[str, ...]
    detection: SubcommandDetection
    check_environment: Mapping[str, str]

    def scope_match(self, scope: RuleScope) -> ScopeMatch:
        return self.detection.match(scope, self.argv)

    def command_name(self, scope: RuleScope) -> str:
        """Name the governed command, such as ``jj git push``, for messages."""
        path = () if scope.subcommand_path is None else scope.subcommand_path
        return " ".join((self.tool.name, *path))


def _rule_reasons(context: _EvaluationContext, rule: Rule) -> list[str]:
    match rule:
        case RefuseOptionRule():
            return _refuse_option_reasons(context, rule)
        case RefuseSubcommandRule():
            if context.scope_match(rule.scope) is not ScopeMatch.COVERED:
                return []
            return [f"it runs `{context.command_name(rule.scope)}`"]
        case AllowlistRule():
            return _allowlist_reasons(context, rule)


def _refuse_option_reasons(context: _EvaluationContext, rule: RefuseOptionRule) -> list[str]:
    if context.scope_match(rule.scope) is not ScopeMatch.COVERED:
        return []

    # Every token before `--` is scanned, including tokens another option
    # might consume as its value, so a refused option cannot hide there.
    used: list[str] = []
    for index in range(operands_start(context.argv)):
        option = match_option(context.argv, index, rule.refused_options, is_global=False)
        if option is not None and option.spelling not in used:
            used.append(option.spelling)
    return [f"it uses `{spelling}`" for spelling in used]


def _allowlist_reasons(context: _EvaluationContext, rule: AllowlistRule) -> list[str]:
    command = context.command_name(rule.scope)
    match context.scope_match(rule.scope):
        case ScopeMatch.NOT_COVERED:
            return []
        case ScopeMatch.UNDETERMINED:
            stopping_index = context.detection.stopping_option_index
            stopping_option = context.argv[stopping_index] if stopping_index is not None else ""
            return [f"`{stopping_option}` keeps the policy from telling whether this is `{command}`"]
        case ScopeMatch.COVERED:
            pass

    invocation = parse_invocation(context.tool, context.argv, rule.allowed_options)
    left_to_other_rules = _options_refused_elsewhere(context)
    reasons: list[str] = []
    for option in invocation.options:
        reasons.extend(_option_reasons(rule, option, command, left_to_other_rules))

    is_informational = len(invocation.occurrences_of(rule.informational_options)) > 0
    has_target = len(invocation.occurrences_of(rule.target_options)) > 0
    if len(rule.target_options) > 0 and not is_informational and not has_target:
        targets = [
            "/".join(f"`{name}`" for name in declaration.names)
            for declaration in rule.allowed_options
            if declaration in rule.target_options
        ]
        reasons.append(f"it names nothing to act on; name each target with {_or_list(targets)}")
    if len(reasons) > 0 or is_informational:
        return reasons

    return _check_reasons(context, rule, invocation)


def _or_list(items: Sequence[str]) -> str:
    """Join ITEMS as ``a, b, or c``."""
    if len(items) <= 2:
        return " or ".join(items)
    return f"{', '.join(items[:-1])}, or {items[-1]}"


def _options_refused_elsewhere(context: _EvaluationContext) -> frozenset[str]:
    """Return the option names that in-scope refuse-option rules already judge."""
    return frozenset(
        name
        for rule in context.tool.rules
        if isinstance(rule, RefuseOptionRule) and context.scope_match(rule.scope) is ScopeMatch.COVERED
        for declaration in rule.refused_options
        for name in declaration.names
    )


def _option_reasons(
    rule: AllowlistRule,
    option: OptionOccurrence,
    command: str,
    left_to_other_rules: frozenset[str],
) -> list[str]:
    if option.spelling in left_to_other_rules:
        return []
    declaration = option.declaration
    if declaration is None:
        return [f"`{option.spelling}` is not an allowed option for `{command}`"]
    if option.is_global:
        if declaration not in rule.allowed_global_options:
            return [f"global option `{option.spelling}` is not allowed for `{command}`"]

    match declaration.arity:
        case OptionArity.FLAG if option.value is not None:
            return [f"`{option.spelling}` takes no value"]
        case OptionArity.VALUE if option.value is None:
            return [
                f"`{option.spelling}` needs a value"
                + f" (write `{option.spelling}=<value>` when the value starts with `-`)"
            ]
        case _:
            pass
    if option.value is None or declaration.value_constraint is None:
        return []

    problem = _value_constraint_problem(declaration.value_constraint, option.value)
    return [] if problem is None else [f"`{option.spelling}` value `{option.value}` {problem}"]


def _value_constraint_problem(constraint: ValueConstraint, value: str) -> str | None:
    """Describe how VALUE breaks CONSTRAINT, or return ``None`` when it holds."""
    match constraint:
        case ValueConstraint.LITERAL_NAME:
            return literal_name_problem(value)
        case ValueConstraint.LITERAL_NAME_BEFORE_EQUALS:
            name, separator, _ = value.partition("=")
            if separator == "":
                return "must have the form `<name>=<value>`"
            problem = literal_name_problem(name)
            return None if problem is None else f"has a name part that {problem}"


# Characters that make a jj string pattern or pattern expression match more
# than one name (globs, alternation, set operators, quoting, kind prefixes).
_PATTERN_CHARACTERS = re.compile(r"[*?\[\]{}|&~()\"'\\:\s]")
_EXACT_PREFIX = "exact:"
# A jj string literal without escapes: one double-quoted string, which jj
# matches exactly and which is the only form jj accepts for names such as
# `renovate/foo@2`.
_QUOTED_NAME = re.compile(r'"([^"\\]*)"')


def literal_name_problem(value: str) -> str | None:
    """Describe why VALUE does not name exactly one thing, or return ``None``.

    A literal name is non-empty and free of pattern syntax. It may carry the
    ``exact:`` pattern kind, the only prefix accepted, or be wrapped in one
    pair of double quotes with no inner ``"`` or ``\\``; the quoted name must
    itself be free of pattern syntax.
    """
    quoted_name = _QUOTED_NAME.fullmatch(value)
    name = value.removeprefix(_EXACT_PREFIX) if quoted_name is None else quoted_name.group(1)
    if name == "":
        return "is empty; name exactly one thing"
    if _PATTERN_CHARACTERS.search(name) is not None:
        return (
            "is a pattern; name exactly one thing with a plain name,"
            + f" `{_EXACT_PREFIX}<name>`, or `\"<name>\"`"
        )
    return None


def _check_reasons(
    context: _EvaluationContext,
    rule: AllowlistRule,
    invocation: ParsedInvocation,
) -> list[str]:
    request = CheckRequest(
        rule=rule,
        invocation=invocation,
        real_command=context.tool.real_command,
        environment=context.check_environment,
    )

    reasons: list[str] = []
    for name in rule.checks:
        try:
            refusal = NAMED_CHECKS[name](request)
        except Exception as error:  # Any check failure must refuse.
            reasons.append(f"check `{name}` failed unexpectedly: {error}")
            continue
        if refusal is not None:
            reasons.append(refusal.reason)
    return reasons
