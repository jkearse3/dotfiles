#!/usr/bin/env python3

from __future__ import annotations

import os
import subprocess
import unittest

FORMATTER = os.environ["FORMATTER"]
CHECKER = os.environ["CHECKER"]


def format_message(message: str, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [FORMATTER, *args],
        input=message,
        text=True,
        capture_output=True,
        check=False,
    )


def check_message(message: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [CHECKER], input=message, text=True, capture_output=True, check=False
    )


class CommitMessageFormatTests(unittest.TestCase):
    def test_empty_input_stays_empty(self) -> None:
        self.assertEqual(format_message("").stdout, "")

    def test_nonempty_output_has_exactly_one_terminal_newline(self) -> None:
        output = format_message("feat: add formatter\n\n\n").stdout
        self.assertEqual(output, "feat: add formatter\n")

    def test_invalid_width_is_rejected(self) -> None:
        result = format_message("feat: add formatter", "--body-width", "0")
        self.assertEqual(result.returncode, 2)
        self.assertIn("must be a positive integer", result.stderr)

    def test_default_width_wraps_only_overlong_prose(self) -> None:
        short = "This short line stays where it was."
        long = "This ordinary prose line contains enough words that it must wrap at the default body width without changing any words."
        message = f"feat: add formatter\n\n{short}\n\n{long}"
        output = format_message(message).stdout
        lines = output.splitlines()
        self.assertEqual(lines[2], short)
        self.assertEqual(lines[3], "")
        self.assertTrue(all(len(line) <= 72 for line in lines[4:]))
        self.assertEqual(" ".join(lines[4:]), long)

    def test_lists_and_trailers_use_continuation_indentation(self) -> None:
        message = (
            "feat: add formatter\n\n"
            "  - This list entry has enough words to wrap with a hanging indentation.\n\n"
            "BREAKING CHANGE: This trailer value has enough words to wrap safely."
        )
        output = format_message(message, "--body-width", "40").stdout
        lines = output.splitlines()
        self.assertTrue(lines[2].startswith("  - "))
        self.assertTrue(lines[3].startswith("    "))
        self.assertTrue(lines[5].startswith("BREAKING CHANGE: "))
        self.assertTrue(lines[6].startswith("  "))
        self.assertTrue(all(len(line) <= 40 for line in lines[2:]))

    def test_urls_and_inline_code_are_not_split(self) -> None:
        url = "https://example.com/" + "a" * 80
        code = "`command --with a value that is intentionally far too long for one line`"
        message = f"docs: explain formatter\n\nSee {url}\n\nUse {code} when testing."
        output = format_message(message).stdout
        self.assertIn(url, output)
        self.assertIn(code, output)
        self.assertEqual(check_message(output).returncode, 0)

    def test_preformatted_content_is_preserved_and_rejected(self) -> None:
        preformatted = "    " + "x" * 80
        message = f"test: preserve sample\n\n{preformatted}"
        output = format_message(message).stdout
        self.assertIn(preformatted, output)
        self.assertNotEqual(check_message(output).returncode, 0)

    def test_ambiguous_command_is_preserved_and_rejected(self) -> None:
        command = "nix build --no-link .#a-very-long-package-name-" + "x" * 50
        message = f"test: preserve command\n\n{command}"
        output = format_message(message).stdout
        self.assertIn(command, output)
        self.assertNotEqual(check_message(output).returncode, 0)

    def test_fenced_content_is_preserved_and_rejected(self) -> None:
        payload = "print('" + "x" * 80 + "')"
        message = (
            f"test: preserve fixture\n\n```python\n{payload}\n"
            f"```not-a-closing-fence\n{payload}\n```"
        )
        output = format_message(message).stdout
        self.assertEqual(output, message + "\n")
        self.assertNotEqual(check_message(output).returncode, 0)

    def test_subject_changes_only_when_valid_except_for_period(self) -> None:
        valid = format_message("feat: add formatter.\n").stdout
        invalid = format_message("noop: Add formatter.\n").stdout
        overlong_subject = "feat: " + "a" * 70 + "."
        overlong = format_message(overlong_subject).stdout
        self.assertEqual(valid, "feat: add formatter\n")
        self.assertEqual(invalid, "noop: Add formatter.\n")
        self.assertEqual(overlong, overlong_subject + "\n")
        self.assertNotEqual(check_message(invalid).returncode, 0)
        self.assertNotEqual(check_message(overlong).returncode, 0)

    def test_supported_output_is_valid_and_idempotent(self) -> None:
        message = (
            "feat: format descriptions.\n\n"
            "This body contains enough ordinary prose to require deterministic wrapping at a narrow configured width.\n\n"
            "Fixes: This trailer value also needs deterministic wrapping for the checker."
        )
        first = format_message(message, "--body-width", "50").stdout
        second = format_message(first, "--body-width", "50").stdout
        self.assertEqual(first, second)
        self.assertEqual(check_message(first).returncode, 0)


if __name__ == "__main__":
    _ = unittest.main()
