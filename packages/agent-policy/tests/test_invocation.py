from __future__ import annotations

import unittest
from typing import final

from agent_policy.invocation import ScopeMatch, detect_subcommand, parse_invocation
from agent_policy.policy import OptionArity, OptionDeclaration, RuleScope, Tool, parse_policy

from policy_fixtures import policy_document

POLICY = parse_policy(policy_document())
JJ: Tool = POLICY.tools["jj"]
GIT: Tool = POLICY.tools["git"]
BOOKMARK = OptionDeclaration(("-b", "--bookmark"), OptionArity.VALUE)
DRY_RUN = OptionDeclaration(("--dry-run",), OptionArity.FLAG)
GIT_PUSH_SCOPE = RuleScope(("git", "push"))


def scope_match(tool: Tool, argv: list[str], scope: RuleScope = GIT_PUSH_SCOPE) -> ScopeMatch:
    return detect_subcommand(tool, argv).match(scope, argv)


@final
class OptionValueFormTests(unittest.TestCase):
    """Value-taking options accept every documented spelling."""

    def test_value_forms_yield_the_same_value(self) -> None:
        for argv in (
            ["-b", "main"],
            ["-bmain"],
            ["-b=main"],
            ["--bookmark", "main"],
            ["--bookmark=main"],
        ):
            with self.subTest(argv=argv):
                [option] = parse_invocation(JJ, argv, [BOOKMARK]).options
                self.assertIs(BOOKMARK, option.declaration)
                self.assertEqual("main", option.value)
                self.assertEqual(len(argv), option.end)

    def test_separate_value_starting_with_dash_is_not_consumed(self) -> None:
        options = parse_invocation(JJ, ["-b", "--all"], [BOOKMARK]).options
        self.assertEqual([None, None], [option.value for option in options])
        self.assertEqual(["-b", "--all"], [option.spelling for option in options])
        self.assertIsNone(options[1].declaration)

    def test_flag_with_attached_value_keeps_the_value_for_reporting(self) -> None:
        [option] = parse_invocation(JJ, ["--dry-run=yes"], [DRY_RUN]).options
        self.assertEqual("yes", option.value)

    def test_long_name_prefix_is_not_a_match(self) -> None:
        [option] = parse_invocation(JJ, ["--bookmarks=x"], [BOOKMARK]).options
        self.assertIsNone(option.declaration)
        self.assertEqual("--bookmarks", option.spelling)

    def test_tokens_after_double_dash_are_operands(self) -> None:
        invocation = parse_invocation(JJ, ["-b", "x", "--", "--ignore-immutable"], [BOOKMARK])
        self.assertEqual(2, invocation.operands_start)
        self.assertEqual(["-b"], [option.spelling for option in invocation.options])

    def test_optional_value_takes_only_attached_values(self) -> None:
        options = parse_invocation(GIT, ["--exec-path", "push"], []).options
        self.assertEqual([None], [option.value for option in options])
        options = parse_invocation(GIT, ["--exec-path=/x", "push"], []).options
        self.assertEqual(["/x"], [option.value for option in options])


@final
class SubcommandDetectionTests(unittest.TestCase):
    """Subcommand words skip declared globals where the tool accepts them."""

    def test_jj_globals_anywhere_do_not_hide_the_subcommand(self) -> None:
        for argv in (
            ["git", "push", "-b", "x"],
            ["-R", "repo", "git", "push"],
            ["git", "--quiet", "push"],
            ["git", "-Rrepo", "push"],
            ["--color=never", "git", "--at-op", "@", "push"],
        ):
            with self.subTest(argv=argv):
                self.assertIs(ScopeMatch.COVERED, scope_match(JJ, argv))

    def test_other_commands_are_not_covered(self) -> None:
        argv: list[str]
        for argv in (["log"], ["git", "fetch"], ["--version"], [], ["git", "--", "push"]):
            with self.subTest(argv=argv):
                self.assertIs(ScopeMatch.NOT_COVERED, scope_match(JJ, argv))

    def test_undeclared_option_before_scope_words_is_undetermined(self) -> None:
        for argv in (["--unknown", "git", "push"], ["git", "-x", "value", "push"]):
            with self.subTest(argv=argv):
                self.assertIs(ScopeMatch.UNDETERMINED, scope_match(JJ, argv))
        self.assertIs(ScopeMatch.NOT_COVERED, scope_match(JJ, ["--unknown", "log"]))

    def test_git_globals_only_before_subcommand(self) -> None:
        push = RuleScope(("push",))
        for argv in (
            ["push"],
            ["-C", "repo", "push", "origin"],
            ["-crepo.x=1", "--no-pager", "push"],
            ["--git-dir=.git", "--exec-path", "push"],
        ):
            with self.subTest(argv=argv):
                self.assertIs(ScopeMatch.COVERED, scope_match(GIT, argv, push))
        detection = detect_subcommand(GIT, ["status", "-C", "x"])
        self.assertEqual(("status",), detection.words)
        self.assertEqual(1, detection.stopping_option_index)

    def test_any_scope_covers_everything(self) -> None:
        self.assertIs(ScopeMatch.COVERED, scope_match(JJ, ["--weird"], RuleScope(None)))
