"""Command-line entry point: run a governed command or validate a policy file.

``agent-policy run --policy <file> <tool> -- <argv...>`` evaluates the tool's
rules for argv. When nothing is refused it replaces itself with the real
binary, passing the tool's prefix arguments and argv, with
``AGENT_POLICY_APPROVE`` removed from the environment. Otherwise it prints one
corrective message per refused rule to stderr, each prefixed
``<tool> (agent policy): ``, and exits 1. A policy that cannot be loaded, an
unknown tool, or an internal error also refuses (exit 2): the engine never
runs the real binary unless evaluation completed.

``agent-policy validate <file>`` reports every schema problem and exits 1 when
there is any, so a Nix build that runs it rejects an invalid policy.
"""

from __future__ import annotations

import argparse
import os
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import NoReturn, TextIO

from .evaluation import APPROVAL_VARIABLE, Refusal, evaluate, without_approval
from .policy import PolicyError, Tool, load_policy

EXIT_REFUSED = 1
EXIT_POLICY_ERROR = 2
EXIT_EXEC_FAILED = 126


def main(arguments: Sequence[str] | None = None) -> int:
    """Run the CLI with ARGUMENTS (default: ``sys.argv[1:]``)."""
    arguments = list(sys.argv[1:] if arguments is None else arguments)

    # The governed argv follows the first `--` and is never parsed as
    # agent-policy options.
    separator = arguments.index("--") if "--" in arguments else None
    own_arguments = arguments if separator is None else arguments[:separator]
    tool_argv = [] if separator is None else arguments[separator + 1 :]

    parser = _parser()
    parsed = parser.parse_args(own_arguments)
    match parsed.command:
        case "run":
            if separator is None:
                parser.error("run needs `--` before the tool's arguments")
            return run(Path(parsed.policy), parsed.tool, tool_argv, os.environ, sys.stderr)
        case _:
            if separator is not None:
                parser.error("validate takes no arguments after `--`")
            return validate(Path(parsed.policy_file), sys.stderr)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="agent-policy",
        description="Decide whether a coding agent's command runs, from a declarative policy.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    run_parser = subparsers.add_parser(
        "run",
        help="evaluate a governed command and run it when allowed",
        usage="agent-policy run --policy POLICY TOOL -- [ARGUMENT ...]",
        description=(
            "Evaluate TOOL's rules for the arguments after `--`; run the real binary when"
            + f" nothing is refused. {APPROVAL_VARIABLE}=<rule-id>[,<rule-id>...] approves"
            + " the listed rules for this one command."
        ),
    )
    _ = run_parser.add_argument("--policy", required=True, help="policy JSON file")
    _ = run_parser.add_argument("tool", help="governed tool name in the policy")

    validate_parser = subparsers.add_parser(
        "validate",
        help="check a policy file against the schema",
        description="Report every problem in POLICY_FILE; exit 1 when there is any.",
    )
    _ = validate_parser.add_argument("policy_file", help="policy JSON file")
    return parser


def run(
    policy_path: Path,
    tool_name: str,
    argv: Sequence[str],
    environment: Mapping[str, str],
    stderr: TextIO,
) -> int:
    """Evaluate ARGV for TOOL_NAME and exec the real binary when allowed.

    Returns an exit status only when the command is refused or cannot run;
    on success the process is replaced and this never returns.
    """
    prefix = f"{tool_name} (agent policy): "
    try:
        policy = load_policy(policy_path)
        tool = policy.tools.get(tool_name)
        if tool is None:
            print(f"{prefix}{tool_name!r} is not a tool in policy {policy_path}; refusing to run it.", file=stderr)
            return EXIT_POLICY_ERROR
        refusals = evaluate(tool, argv, environment)
    except PolicyError as error:
        print(f"{prefix}cannot load policy {policy_path}: {error}; refusing to run {tool_name}.", file=stderr)
        return EXIT_POLICY_ERROR
    except Exception as error:  # An engine failure must refuse, never exec.
        print(f"{prefix}internal error ({type(error).__name__}: {error}); refusing to run {tool_name}.", file=stderr)
        return EXIT_POLICY_ERROR

    if len(refusals) > 0:
        for line in refusal_lines(refusals):
            print(prefix + line, file=stderr)
        return EXIT_REFUSED

    _exec_tool(tool, argv, environment, prefix, stderr)


def refusal_lines(refusals: Sequence[Refusal]) -> list[str]:
    """Format one corrective line per refusal, plus a combined approval hint.

    Each line names the rule ID, the reasons, the rule's message, and how to
    request the user's approval for that rule.
    """
    lines = [
        f"{refusal.rule.id} refused this command: {'; '.join(refusal.reasons)}. {refusal.rule.message}"
        + f" {approval_instruction(refusal.rule.id)}"
        for refusal in refusals
    ]
    if len(refusals) > 1:
        rule_ids = ",".join(refusal.rule.id for refusal in refusals)
        lines.append(f"To request approval for all of these at once, use `{APPROVAL_VARIABLE}={rule_ids}`.")
    return lines


def approval_instruction(rule_ids: str) -> str:
    """Tell the agent how to request the user's approval for RULE_IDS."""
    return (
        f"Running it anyway needs the user's approval: to request it, rerun this same single command"
        + f" prefixed with `{APPROVAL_VARIABLE}={rule_ids}` (never export the variable), and the user will be asked."
    )


def _exec_tool(
    tool: Tool,
    argv: Sequence[str],
    environment: Mapping[str, str],
    prefix: str,
    stderr: TextIO,
) -> NoReturn:
    command = [*tool.real_command, *argv]
    try:
        os.execve(tool.executable, command, without_approval(environment))
    except OSError as error:
        print(f"{prefix}cannot run {tool.executable}: {error}", file=stderr)
        raise SystemExit(EXIT_EXEC_FAILED) from error


def validate(policy_path: Path, stderr: TextIO) -> int:
    """Report every problem in the policy at POLICY_PATH; return 1 if any."""
    try:
        _ = load_policy(policy_path)
    except PolicyError as error:
        for problem in error.problems:
            print(f"agent-policy: {policy_path}: {problem}", file=stderr)
        return 1
    return 0
