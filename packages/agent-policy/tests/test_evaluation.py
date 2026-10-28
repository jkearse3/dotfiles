from __future__ import annotations

import unittest
from typing import final, override
from unittest.mock import patch

from agent_policy.checks import NAMED_CHECKS, CheckRefusal, CheckRequest, NamedCheck
from agent_policy.evaluation import approved_rule_ids, evaluate, literal_name_problem
from agent_policy.policy import Policy, parse_policy

from policy_fixtures import JsonObject, jj_git_push_rule, jj_tool, policy_document

POLICY = parse_policy(policy_document())


def refused(tool: str, argv: list[str], environment: dict[str, str] | None = None) -> dict[str, list[str]]:
    """Return refusals for ARGV as {rule ID: reasons}."""
    refusals = evaluate(POLICY.tools[tool], argv, {} if environment is None else environment)
    return {refusal.rule.id: list(refusal.reasons) for refusal in refusals}


@final
class RefuseRuleTests(unittest.TestCase):
    """refuse-option and refuse-subcommand rules."""

    def test_refused_option_anywhere_before_double_dash(self) -> None:
        for argv in (
            ["--ignore-immutable", "abandon"],
            ["abandon", "x", "--ignore-immutable"],
            ["describe", "-m", "--ignore-immutable"],
            ["log", "--ignore-immutable=true"],
        ):
            with self.subTest(argv=argv):
                self.assertEqual(["jj.ignore-immutable"], list(refused("jj", argv)))

    def test_refused_option_after_double_dash_is_an_operand(self) -> None:
        self.assertEqual({}, refused("jj", ["file", "show", "--", "--ignore-immutable"]))

    def test_refused_subcommand_with_globals(self) -> None:
        for argv in (
            ["push"],
            ["push", "--force", "origin"],
            ["-C", "repo", "push"],
            ["-c", "x=y", "--no-pager", "push"],
            ["--exec-path=/x", "push"],
        ):
            with self.subTest(argv=argv):
                self.assertEqual({"git.push": ["it runs `git push`"]}, refused("git", argv))

    def test_undeclared_global_ends_detection_for_refuse_rules(self) -> None:
        for argv in (["--unknown", "push"], ["status"], ["-c"], ["log", "push"]):
            with self.subTest(argv=argv):
                self.assertEqual({}, refused("git", argv))


@final
class AllowlistTests(unittest.TestCase):
    """The jj.git-push-shaped allowlist."""

    def test_allowed_forms_pass(self) -> None:
        for argv in (
            ["git", "push", "-b", "main"],
            ["git", "push", "-b", "a", "--bookmark=b", "-bc", "--remote", "origin"],
            ["git", "push", "-c", "all()"],
            ["git", "push", "--named", "feature=@-"],
            ["git", "push", "-b", "exact:main", "--dry-run"],
            ["git", "push", "--bookmark", "\"renovate/foo@2\"", "--dry-run"],
            ["git", "push", "--named", "\"feature\"=@-"],
            ["-R", "repo", "git", "--quiet", "push", "-b", "x", "--color=never"],
            ["git", "push", "--help"],
            ["git", "push", "-h", "-c", "@"],
        ):
            with self.subTest(argv=argv):
                self.assertEqual({}, refused("jj", argv))

    def test_refusals_name_the_offending_input(self) -> None:
        cases = {
            ("git", "push"): "names nothing to act on",
            ("git", "push", "--all"): "`--all` is not an allowed option for `jj git push`",
            ("git", "push", "-b", "x", "--unknown"): "`--unknown` is not an allowed option",
            ("git", "push", "-b", "*"): "`-b` value `*` is a pattern",
            ("git", "push", "-b", "glob:x*"): "`-b` value `glob:x*` is a pattern",
            ("git", "push", "-b", "a|b"): "is a pattern",
            ("git", "push", "-b", "x", "--remote", "*"): "`--remote` value `*` is a pattern",
            ("git", "push", "--named", "x*=@"): "has a name part that is a pattern",
            ("git", "push", "--named", "x"): "must have the form `<name>=<value>`",
            ("git", "push", "-b"): "`-b` needs a value",
            ("git", "push", "-b", "--all"): "`-b` needs a value",
            ("git", "push", "-b", "x", "--dry-run=1"): "`--dry-run` takes no value",
            ("--config", "a=b", "git", "push", "-b", "x"): "global option `--config` is not allowed",
            ("git", "push", "-b", "x", "--at-op=@-"): "global option `--at-op` is not allowed",
            ("--unknown", "git", "push", "-b", "x"): "`--unknown` keeps the policy from telling",
        }
        for argv, expected in cases.items():
            with self.subTest(argv=argv):
                result = refused("jj", list(argv))
                self.assertEqual(["jj.git-push"], list(result))
                self.assertIn(expected, "; ".join(result["jj.git-push"]))

    def test_every_offending_option_is_reported(self) -> None:
        result = refused("jj", ["git", "push", "--all", "--tracked", "-b", "*"])
        self.assertEqual(3, len(result["jj.git-push"]))

    def test_option_refused_by_another_rule_is_left_to_it(self) -> None:
        self.assertEqual(
            ["jj.ignore-immutable"],
            list(refused("jj", ["git", "push", "--ignore-immutable", "-b", "x"])),
        )

    def test_undeclared_option_refused_by_another_rule_is_left_to_it(self) -> None:
        refuse_force: JsonObject = {
            "id": "jj.force",
            "kind": "refuse-option",
            "scope": ["git", "push"],
            "refused-options": ["--force"],
            "message": "No forcing.",
        }
        policy = parse_policy(policy_document(jj=jj_tool(rules=[refuse_force, jj_git_push_rule()])))
        refusals = evaluate(policy.tools["jj"], ["git", "push", "-b", "x", "--force"], {})
        self.assertEqual(["jj.force"], [refusal.rule.id for refusal in refusals])

    def test_both_rules_report_independently(self) -> None:
        result = refused("jj", ["git", "push", "--ignore-immutable", "--all"])
        self.assertEqual(["jj.ignore-immutable", "jj.git-push"], list(result))

    def test_other_commands_ignore_the_allowlist(self) -> None:
        for argv in (["log", "--all"], ["git", "fetch", "--all-remotes"], ["--unknown", "log"]):
            with self.subTest(argv=argv):
                self.assertEqual({}, refused("jj", argv))

    def test_literal_name(self) -> None:
        for value in ("main", "feature/x-1", "exact:main", "v1.0", "\"main\"", "\"renovate/foo@2\""):
            with self.subTest(value=value):
                self.assertIsNone(literal_name_problem(value))
        for value in ("", "exact:", "*", "a?", "[ab]", "{a,b}", "regex:x", "substring:x", "exact-i:x",
                      "~x", "a & b", "a b", "exact:a*", "\"\"", "\"x", "x\"", "\"a\"b\"", "\"a\\\\b\"",
                      "\"a\" | \"b\"", "\"*\"", "\"glob:x\"", "exact:\"x\"", "'x'"):
            with self.subTest(value=value):
                self.assertIsNotNone(literal_name_problem(value))


@final
class ApprovalTests(unittest.TestCase):
    """AGENT_POLICY_APPROVE lists exact rule IDs."""

    def test_approved_ids_parse(self) -> None:
        self.assertEqual(frozenset(), approved_rule_ids(None))
        self.assertEqual(frozenset(), approved_rule_ids(""))
        self.assertEqual(frozenset({"a.b", "c.d"}), approved_rule_ids(" a.b, ,c.d"))

    def test_approval_matrix(self) -> None:
        argv = ["git", "push", "--all"]
        cases: list[tuple[str, list[str]]] = [
            ("jj.git-push", []),
            ("jj.ignore-immutable,jj.git-push", []),
            ("jj.ignore-immutable", ["jj.git-push"]),
            ("1", ["jj.git-push"]),
            ("*", ["jj.git-push"]),
            ("jj.git-push-x", ["jj.git-push"]),
            ("", ["jj.git-push"]),
        ]
        for value, expected in cases:
            with self.subTest(value=value):
                result = refused("jj", argv, {"AGENT_POLICY_APPROVE": value})
                self.assertEqual(expected, list(result))

    def test_approval_covers_only_its_rule(self) -> None:
        result = refused(
            "jj",
            ["git", "push", "--ignore-immutable", "--all"],
            {"AGENT_POLICY_APPROVE": "jj.ignore-immutable"},
        )
        self.assertEqual(["jj.git-push"], list(result))


def _policy_with_check(check_name: str) -> Policy:
    rule = jj_git_push_rule({"checks": [check_name]})
    return parse_policy(policy_document(jj=jj_tool(rules=[rule])))


@final
class NamedCheckTests(unittest.TestCase):
    """Named checks run after the allowlist and report under its rule."""

    @override
    def setUp(self) -> None:
        self.requests: list[CheckRequest] = []

    def _record(self, refusal: CheckRefusal | None) -> NamedCheck:
        def check(request: CheckRequest) -> CheckRefusal | None:
            self.requests.append(request)
            return refusal

        return check

    def test_check_sees_invocation_command_environment_and_rule(self) -> None:
        with patch.dict(NAMED_CHECKS, {"test-check": self._record(None)}):
            tool = _policy_with_check("test-check").tools["jj"]
            refusals = evaluate(
                tool,
                ["git", "push", "-b", "x", "-c", "@"],
                {"AGENT_POLICY_APPROVE": "other.rule", "HOME": "/home"},
            )

        self.assertEqual([], refusals)
        [request] = self.requests
        self.assertEqual(("/bin/jj", "--config", "ui.editor=denied"), request.real_command)
        self.assertEqual({"HOME": "/home"}, dict(request.environment))
        self.assertEqual("jj.git-push", request.rule.id)
        targets = request.invocation.occurrences_of(request.rule.target_options)
        self.assertEqual(["x", "@"], [option.value for option in targets])

    def test_check_refusal_belongs_to_the_owning_rule(self) -> None:
        with patch.dict(NAMED_CHECKS, {"test-check": self._record(CheckRefusal("it moves `x` backward"))}):
            tool = _policy_with_check("test-check").tools["jj"]
            refusals = evaluate(tool, ["git", "push", "-b", "x"], {})
        self.assertEqual([("jj.git-push", ("it moves `x` backward",))], [(r.rule.id, r.reasons) for r in refusals])

    def test_check_is_skipped_when_approved_declaratively_refused_or_informational(self) -> None:
        with patch.dict(NAMED_CHECKS, {"test-check": self._record(CheckRefusal("no"))}):
            tool = _policy_with_check("test-check").tools["jj"]
            approved = evaluate(tool, ["git", "push", "-b", "x"], {"AGENT_POLICY_APPROVE": "jj.git-push"})
            declarative = evaluate(tool, ["git", "push", "--all"], {})
            informational = evaluate(tool, ["git", "push", "--help"], {})
        self.assertEqual([], approved)
        self.assertEqual([], informational)
        self.assertNotIn("no", declarative[0].reasons)
        self.assertEqual([], self.requests)

    def test_check_exception_refuses(self) -> None:
        def broken(_request: CheckRequest) -> CheckRefusal | None:
            raise RuntimeError("boom")

        with patch.dict(NAMED_CHECKS, {"test-check": broken}):
            tool = _policy_with_check("test-check").tools["jj"]
            [refusal] = evaluate(tool, ["git", "push", "-b", "x"], {})
        self.assertEqual("jj.git-push", refusal.rule.id)
        self.assertIn("boom", refusal.reasons[0])
