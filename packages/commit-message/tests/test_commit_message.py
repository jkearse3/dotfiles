from __future__ import annotations

import os
import subprocess
import unittest

CLI = os.environ["COMMIT_MESSAGE"]


def run_cli(command: str, message: str, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [CLI, command, *args],
        input=message,
        text=True,
        capture_output=True,
        check=False,
    )


def format_message(message: str, *args: str) -> subprocess.CompletedProcess[str]:
    return run_cli("format", message, *args)


def validate_message(message: str, *args: str) -> subprocess.CompletedProcess[str]:
    return run_cli("validate", message, *args)


class CommitMessageTests(unittest.TestCase):
    def test_empty_input_stays_empty_but_is_invalid(self) -> None:
        self.assertEqual(format_message("").stdout, "")
        result = validate_message("")
        self.assertEqual(result.returncode, 1)
        self.assertIn("line 1: subject is required", result.stderr)

    def test_nonempty_output_has_exactly_one_terminal_newline(self) -> None:
        output = format_message("feat: add formatter\n\n\n").stdout
        self.assertEqual(output, "feat: add formatter\n")

    def test_invalid_widths_are_argparse_errors(self) -> None:
        for command, arguments in (
            ("format", ("--body-width", "0")),
            ("validate", ("--subject-width", "nope")),
            ("validate", ("--body-width", "-1")),
        ):
            with self.subTest(command=command, arguments=arguments):
                result = run_cli(command, "feat: test", *arguments)
                self.assertEqual(result.returncode, 2)
                self.assertIn("must be a positive integer", result.stderr)

    def test_validator_accepts_plain_subjects_and_conventional_variants(self) -> None:
        for message in (
            "feat(vcs)!: add commit message validator\n\nBody line within limit.\n",
            "add a thing\n",
            "api: added some endpoint\n",
            "noop: add validator\n",
            "feat(): add validator\n",
            "feat: Add validator\n",
            "feat: add validator.\n",
        ):
            with self.subTest(message=message):
                self.assertEqual(validate_message(message).returncode, 0)

    def test_validator_reports_subject_and_body_widths(self) -> None:
        subject = validate_message(
            "plain subject longer than twenty characters\n", "--subject-width", "20"
        )
        self.assertEqual(subject.returncode, 1)
        self.assertIn("line 1: subject is", subject.stderr)

        body = validate_message(
            "docs: add note\n\nordinary body line longer\n", "--body-width", "20"
        )
        self.assertEqual(body.returncode, 1)
        self.assertIn("line 3: body/footer line", body.stderr)

    def test_default_width_wraps_only_overlong_prose(self) -> None:
        short = "This short line stays where it was."
        long = "This ordinary prose line contains enough words that it must wrap at the default body width without changing any words."
        output = format_message(f"feat: add formatter\n\n{short}\n\n{long}").stdout
        lines = output.splitlines()
        self.assertEqual(lines[2], short)
        self.assertEqual(lines[3], "")
        self.assertTrue(all(len(line) <= 72 for line in lines[4:]))
        self.assertEqual(" ".join(lines[4:]), long)

    def test_reflows_existing_prose_lines_as_one_paragraph(self) -> None:
        message = (
            "fix(vcs): accept plain commit subjects\n\n"
            "The validator previously required every subject to use Conventional Commit\n"
            "syntax, rejecting valid repository-specific forms. Limit subject\n"
            "validation\n"
            "to presence and width while retaining body width checks; agent-authored\n"
            "descriptions remain governed by separate Conventional Commit guidance."
        )
        output = format_message(message).stdout
        body = output.splitlines()[2:]
        expected = " ".join(message.splitlines()[2:])
        self.assertTrue(all(len(line) <= 72 for line in body))
        self.assertEqual(" ".join(body), expected)

    def test_hand_wrapped_paragraph_formats_like_unbroken_paragraph(self) -> None:
        paragraph_lines = (
            "The formatter treats this hand-wrapped paragraph as one logical unit",
            "because `collapsing` intra-paragraph newlines is what a case",
            "statement",
            "document view, once the,",
            "(parenthetical aside) rewrap requires so that no fragment such as",
            "detail lands.",
        )
        hand_wrapped = "feat: demo\n\n" + "\n".join(paragraph_lines)
        unbroken = "feat: demo\n\n" + " ".join(paragraph_lines)

        output = format_message(hand_wrapped).stdout
        self.assertEqual(output, format_message(unbroken).stdout)
        self.assertTrue(all(len(line) <= 72 for line in output.splitlines()))

    def test_prose_paragraph_opening_with_word_colon_is_not_a_trailer(self) -> None:
        message = (
            "feat: demo\n\n"
            "Records: hold the canonical state for each document and are "
            "rewritten whenever the underlying case data changes in any way."
        )
        body = format_message(message).stdout.splitlines()[2:]
        self.assertTrue(all(len(line) <= 72 for line in body))
        self.assertFalse(any(line.startswith(" ") for line in body))
        self.assertEqual(" ".join(body), message.splitlines()[2])

    def test_patch_lines_directly_after_prose_are_not_absorbed(self) -> None:
        for patch in (
            "--- a/file\n+++ b/file",
            "@@ -1,3 +1,3 @@\n-old_line = 1\n+new_line = 2",
        ):
            with self.subTest(patch=patch):
                message = f"fix: apply patch\n\nApply this change to the loop\n{patch}"
                self.assertEqual(format_message(message).stdout, message + "\n")

    def test_lowercase_trailer_block_is_preserved(self) -> None:
        message = (
            "feat: demo\n\n"
            "signed-off-by: Alpha <a@example.com>\n"
            "co-authored-by: Beta <b@example.com>"
        )
        self.assertEqual(format_message(message).stdout, message + "\n")

    def test_recognized_trailer_keys_keep_hanging_indent(self) -> None:
        for trailer in (
            "Signed-off-by: A reviewer identity long enough to need wrapping.",
            "Fixes: This trailer value has enough words to wrap onto two lines.",
        ):
            with self.subTest(trailer=trailer):
                lines = format_message(
                    f"feat: demo\n\n{trailer}", "--body-width", "40"
                ).stdout.splitlines()
                self.assertEqual(lines[2].split(":")[0], trailer.split(":")[0])
                self.assertTrue(lines[3].startswith("  "))

    def test_lists_and_trailers_use_continuation_indentation(self) -> None:
        message = (
            "feat: add formatter\n\n"
            "  - This list entry has enough words to wrap with a hanging indentation.\n\n"
            "BREAKING CHANGE: This trailer value has enough words to wrap safely."
        )
        lines = format_message(message, "--body-width", "40").stdout.splitlines()
        self.assertTrue(lines[2].startswith("  - "))
        self.assertTrue(lines[3].startswith("    "))
        self.assertTrue(lines[5].startswith("BREAKING CHANGE: "))
        self.assertTrue(lines[6].startswith("  "))
        self.assertTrue(all(len(line) <= 40 for line in lines[2:]))

    def test_issue_footers_remain_on_separate_lines(self) -> None:
        message = "fix: preserve footers\n\nCloses #123\nFixes JIRA-456"
        self.assertEqual(format_message(message).stdout, message + "\n")
        self.assertEqual(
            format_message(message, "--body-width", "10").stdout,
            message + "\n",
        )

    def test_line_sensitive_content_is_preserved(self) -> None:
        message = (
            "docs: preserve structured content\n\n"
            "Hard break.  \n"
            "Next line.\n\n"
            "Hard break ends with `code`  \n"
            "Next line.\n\n"
            "Hard break ends with https://example.com/p  \n"
            "Next line.\n\n"
            "Heading\n"
            "---\n\n"
            "--- a/file\n"
            "+++ b/file\n"
            "old mode 100644\n"
            "new mode 100755\n"
            "-old\n"
            "+new\n\n"
            "State | Status\n"
            "foo | running"
        )
        self.assertEqual(format_message(message).stdout, message + "\n")

    def test_urls_and_inline_code_are_not_split_and_validator_accepts_them(self) -> None:
        url = "https://example.com/" + "a" * 80
        code = "`command --with a value that is intentionally far too long for one line`"
        message = f"docs: explain formatter\n\nSee {url}\n\nUse {code} when testing."
        output = format_message(message).stdout
        self.assertIn(url, output)
        self.assertIn(code, output)
        self.assertEqual(validate_message(output).returncode, 0)

    def test_prose_ending_in_an_unbreakable_span_still_reflows(self) -> None:
        for tail in ("`some code`", "https://example.com/page"):
            with self.subTest(tail=tail):
                message = (
                    "docs: reflow prose\n\n"
                    f"This paragraph ends its first line with {tail}\n"
                    "and joins the next line before wrapping."
                )
                unbroken = message.replace(f"{tail}\n", f"{tail} ")
                output = format_message(message).stdout
                self.assertEqual(output, format_message(unbroken).stdout)
                body = output.splitlines()[2:]
                self.assertIn(tail, " ".join(body))
                self.assertTrue(all(len(line) <= 72 for line in body))

    def test_conservative_formatting_may_remain_invalid(self) -> None:
        samples = (
            "    " + "x" * 80,
            "nix build --no-link .#a-very-long-package-name-" + "x" * 50,
            "```python\nprint('" + "x" * 80 + "')\n```",
        )
        for sample in samples:
            with self.subTest(sample=sample):
                message = f"test: preserve sample\n\n{sample}"
                output = format_message(message).stdout
                self.assertIn(sample, output)
                self.assertEqual(validate_message(output).returncode, 1)

    def test_subject_is_preserved_regardless_of_shape_or_width(self) -> None:
        for subject in (
            "feat: add formatter.",
            "feat: Add formatter.",
            "Added formatter.",
            "api: Added formatter.",
            "a" * 71 + ".",
            "feat: " + "a" * 70 + ".",
            ".",
            "Wait..",
        ):
            with self.subTest(subject=subject):
                self.assertEqual(format_message(subject).stdout, subject + "\n")

    def test_supported_output_is_valid_and_idempotent_at_matching_width(self) -> None:
        message = (
            "feat: format descriptions.\n\n"
            "This body contains enough ordinary prose to require deterministic wrapping at a narrow configured width.\n\n"
            "Fixes: This trailer value also needs deterministic wrapping for validation."
        )
        first = format_message(message, "--body-width", "50").stdout
        second = format_message(first, "--body-width", "50").stdout
        self.assertEqual(first, second)
        self.assertEqual(validate_message(first, "--body-width", "50").returncode, 0)

    def test_check_subcommand_is_rejected(self) -> None:
        result = run_cli("check", "feat: test")
        self.assertEqual(result.returncode, 2)
        self.assertIn("invalid choice: 'check'", result.stderr)


if __name__ == "__main__":
    _ = unittest.main()
