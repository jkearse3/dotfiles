#!/usr/bin/env python3

from __future__ import annotations

import os
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import final, override


PROGRAM = Path(
    os.environ.get(
        "WORKTREE_INCLUDE_PROGRAM", Path(__file__).parents[1] / "worktree-include.py"
    )
)


def run(
    *arguments: str, cwd: Path, check: bool = True, env: dict[str, str] | None = None
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        arguments,
        check=check,
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
    )


@final
class WorktreeIncludeTests(unittest.TestCase):
    root: Path
    primary: Path
    linked: Path

    @override
    def setUp(self) -> None:
        temporary_directory = TemporaryDirectory()
        self.addCleanup(temporary_directory.cleanup)
        self.root = Path(temporary_directory.name).resolve()
        self.primary = self.root / "primary"
        self.linked = self.root / "linked"

        self.primary.mkdir()
        self.git("init", "-q", "-b", "main")
        _ = self.write(".gitignore", ".env*\n.dev.vars\n/local/\n*.log\n")
        _ = self.write("tracked.env.example", "tracked\n")
        self.git("add", "-f", ".gitignore", "tracked.env.example")
        self.git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "init")
        self.git("worktree", "add", "-q", "--detach", str(self.linked))

    def git(self, *arguments: str, cwd: Path | None = None) -> None:
        _ = run("git", *arguments, cwd=cwd if cwd is not None else self.primary)

    def write(self, relative_path: str, content: str, root: Path | None = None) -> Path:
        path = (root if root is not None else self.primary) / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        _ = path.write_text(content)
        return path

    def include(self, *patterns: str) -> None:
        _ = self.write(".worktreeinclude", "".join(f"{pattern}\n" for pattern in patterns))

    def worktree_include(
        self, *arguments: str, cwd: Path | None = None, check: bool = True
    ) -> subprocess.CompletedProcess[str]:
        return run(str(PROGRAM), *arguments, cwd=cwd if cwd is not None else self.linked, check=check)

    def test_copies_only_files_both_included_and_ignored(self) -> None:
        self.include(".env", ".dev.vars", "local/", "untracked.txt", "tracked.env.example")
        _ = self.write(".env", "SECRET=1\n")
        _ = self.write("local/nested/settings.json", "{}\n")
        _ = self.write("untracked.txt", "not ignored\n")
        _ = self.write("debug.log", "ignored but not included\n")
        _ = self.write("tracked.env.example", "modified tracked file\n")

        result = self.worktree_include()

        self.assertEqual("copied .env\ncopied local/nested/settings.json\n", result.stdout)
        self.assertEqual("SECRET=1\n", (self.linked / ".env").read_text())
        self.assertEqual("{}\n", (self.linked / "local/nested/settings.json").read_text())
        self.assertFalse((self.linked / "untracked.txt").exists())
        self.assertFalse((self.linked / "debug.log").exists())
        self.assertEqual("tracked\n", (self.linked / "tracked.env.example").read_text())

    def test_honors_negated_include_patterns(self) -> None:
        self.include("local/**", "!local/skip.json")
        _ = self.write("local/keep.json", "keep\n")
        _ = self.write("local/skip.json", "skip\n")

        _ = self.worktree_include()

        self.assertTrue((self.linked / "local/keep.json").exists())
        self.assertFalse((self.linked / "local/skip.json").exists())

    def test_preserves_file_mode_and_symlinks(self) -> None:
        self.include(".env", ".env.link")
        (self.write(".env", "SECRET=1\n")).chmod(0o600)
        (self.primary / ".env.link").symlink_to(".env")

        _ = self.worktree_include()

        self.assertEqual(0o600, (self.linked / ".env").stat().st_mode & 0o777)
        self.assertEqual(".env", os.readlink(self.linked / ".env.link"))

    def test_missing_include_file_copies_nothing(self) -> None:
        _ = self.write(".env", "SECRET=1\n")

        result = self.worktree_include()

        self.assertEqual("", result.stdout)
        self.assertIn("no .worktreeinclude", result.stderr)
        self.assertFalse((self.linked / ".env").exists())

    def test_never_overwrites_existing_destination_files(self) -> None:
        self.include(".env", ".dev.vars")
        _ = self.write(".env", "SECRET=1\n")
        _ = self.write(".dev.vars", "SOURCE=1\n")
        _ = self.write(".env", "SECRET=1\n", root=self.linked)
        _ = self.write(".dev.vars", "LOCAL_EDIT=1\n", root=self.linked)

        result = self.worktree_include()

        self.assertEqual("unchanged .env\n", result.stdout)
        self.assertIn("kept existing .dev.vars", result.stderr)
        self.assertEqual("LOCAL_EDIT=1\n", (self.linked / ".dev.vars").read_text())

    def test_dry_run_writes_nothing(self) -> None:
        self.include(".env")
        _ = self.write(".env", "SECRET=1\n")

        result = self.worktree_include("--dry-run")

        self.assertEqual("would copy .env\n", result.stdout)
        self.assertFalse((self.linked / ".env").exists())

    def test_explicit_source_and_destination(self) -> None:
        self.include(".env")
        _ = self.write(".env", "SECRET=1\n")

        _ = self.worktree_include("--source", str(self.primary), str(self.linked), cwd=self.root)

        self.assertTrue((self.linked / ".env").exists())

    def test_refuses_the_source_worktree_as_destination(self) -> None:
        self.include(".env")

        result = self.worktree_include(cwd=self.primary, check=False)

        self.assertEqual(1, result.returncode)
        self.assertIn("same worktree", result.stderr)

    def test_refuses_worktrees_of_different_repositories(self) -> None:
        other = self.root / "other"
        other.mkdir()
        self.git("init", "-q", cwd=other)

        result = self.worktree_include("--source", str(self.primary), str(other), check=False)

        self.assertEqual(1, result.returncode)
        self.assertIn("different repositories", result.stderr)

    def test_refuses_to_write_through_a_symlinked_destination_directory(self) -> None:
        self.include("local/")
        _ = self.write("local/settings.json", "{}\n")
        outside = self.root / "outside"
        outside.mkdir()
        (self.linked / "local").symlink_to(outside)

        result = self.worktree_include(check=False)

        self.assertEqual(1, result.returncode)
        self.assertIn("outside the destination worktree", result.stderr)
        self.assertEqual([], list(outside.iterdir()))

    def test_never_selects_jj_metadata(self) -> None:
        self.include("*")
        _ = self.write(".env", "SECRET=1\n")
        _ = self.write(".jj/.gitignore", "/*\n")
        _ = self.write(".jj/repo/config-id", "id\n")

        result = self.worktree_include()

        self.assertEqual("copied .env\n", result.stdout)
        self.assertFalse((self.linked / ".jj").exists())

    def test_refuses_a_destination_parent_that_is_not_a_directory(self) -> None:
        _ = self.write("local/settings.json", "{}\n")
        _ = self.write(".env.d/settings", "SECRET=1\n")
        _ = self.write("local", "a file where a directory is needed\n", root=self.linked)
        (self.linked / ".env.d").symlink_to("missing")

        for blocked in ("local", ".env.d"):
            self.include(f"{blocked}/")
            for arguments in ((), ("--dry-run",)):
                with self.subTest(blocked=blocked, arguments=arguments):
                    result = self.worktree_include(*arguments, check=False)

                    self.assertEqual(1, result.returncode)
                    self.assertEqual("", result.stdout)
                    self.assertEqual(
                        f"worktree-include: cannot create {self.linked / blocked}: "
                        + f"{self.linked / blocked} is not a directory\n",
                        result.stderr,
                    )
        self.assertFalse((self.linked / "missing").exists())

    @unittest.skipIf(os.geteuid() == 0, "root ignores directory mode bits")
    def test_reports_an_unwritable_destination_directory(self) -> None:
        self.include("local/**")
        _ = self.write("local/settings.json", "{}\n")
        read_only = self.linked / "local"
        read_only.mkdir()
        read_only.chmod(0o555)
        self.addCleanup(read_only.chmod, 0o755)

        result = self.worktree_include(check=False)

        self.assertEqual(1, result.returncode)
        self.assertTrue(
            result.stderr.startswith(
                f"worktree-include: could not copy {self.primary / 'local/settings.json'} "
                + f"to {read_only / 'settings.json'}: "
            ),
            result.stderr,
        )
        self.assertEqual(1, len(result.stderr.splitlines()), result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertEqual([], list(read_only.iterdir()))

    @unittest.skipIf(os.geteuid() == 0, "root ignores file mode bits")
    def test_reports_an_unreadable_source_file(self) -> None:
        self.include(".env")
        unreadable = self.write(".env", "SECRET=1\n")
        _ = self.write(".env", "SECRET=2\n", root=self.linked)
        unreadable.chmod(0o000)
        self.addCleanup(unreadable.chmod, 0o600)

        result = self.worktree_include(check=False)

        self.assertEqual(1, result.returncode)
        self.assertEqual("", result.stdout)
        self.assertTrue(
            result.stderr.startswith(
                f"worktree-include: could not copy {unreadable} to {self.linked / '.env'}: "
            ),
            result.stderr,
        )
        self.assertEqual(1, len(result.stderr.splitlines()), result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertEqual("SECRET=2\n", (self.linked / ".env").read_text())


@final
class PostCheckoutHookTests(unittest.TestCase):
    """Drive `--post-checkout` through real Git commands with the hook
    configured in an isolated global Git configuration."""

    root: Path
    primary: Path
    env: dict[str, str]

    @override
    def setUp(self) -> None:
        temporary_directory = TemporaryDirectory()
        self.addCleanup(temporary_directory.cleanup)
        self.root = Path(temporary_directory.name).resolve()
        self.primary = self.root / "primary"

        global_config = self.root / "global.gitconfig"
        _ = global_config.write_text(
            "[hook \"worktree-include\"]\n"
            f"\tcommand = {PROGRAM} --post-checkout\n"
            "\tevent = post-checkout\n"
            "[user]\n"
            "\tname = t\n"
            "\temail = t@t\n"
        )
        self.env = {
            **os.environ,
            "GIT_CONFIG_GLOBAL": str(global_config),
            "GIT_CONFIG_NOSYSTEM": "1",
        }

        self.primary.mkdir()
        _ = self.git("init", "-q", "-b", "main")
        _ = (self.primary / ".gitignore").write_text(".env\n")
        _ = self.git("add", ".gitignore")
        _ = self.git("commit", "-qm", "init")
        _ = (self.primary / ".env").write_text("SECRET=1\n")

    def git(
        self, *arguments: str, cwd: Path | None = None, check: bool = True
    ) -> subprocess.CompletedProcess[str]:
        return run(
            "git",
            *arguments,
            cwd=cwd if cwd is not None else self.primary,
            check=check,
            env=self.env,
        )

    def include(self) -> None:
        _ = (self.primary / ".worktreeinclude").write_text(".env\n")

    def test_worktree_add_populates_the_new_worktree(self) -> None:
        self.include()
        linked = self.root / "linked"

        result = self.git("worktree", "add", "-q", "-b", "feature", str(linked))

        self.assertEqual("SECRET=1\n", (linked / ".env").read_text())
        self.assertIn("copied .env", result.stdout + result.stderr)

    def test_detached_worktree_add_populates_the_new_worktree(self) -> None:
        self.include()
        linked = self.root / "linked"

        _ = self.git("worktree", "add", "-q", "--detach", str(linked))

        self.assertEqual("SECRET=1\n", (linked / ".env").read_text())

    def test_is_silent_without_an_include_file(self) -> None:
        linked = self.root / "linked"

        result = self.git("worktree", "add", "-q", "--detach", str(linked))

        self.assertEqual("", result.stdout + result.stderr)
        self.assertFalse((linked / ".env").exists())

    def test_ignores_clones(self) -> None:
        self.include()
        _ = self.git("add", "-f", ".worktreeinclude")
        _ = self.git("commit", "-qm", "include")
        clone = self.root / "clone"

        result = self.git("clone", "-q", str(self.primary), str(clone), cwd=self.root)

        self.assertEqual("", result.stdout + result.stderr)
        self.assertFalse((clone / ".env").exists())

    def test_ignores_ordinary_checkouts_in_linked_worktrees(self) -> None:
        linked = self.root / "linked"
        _ = self.git("worktree", "add", "-q", "--detach", str(linked))
        self.include()

        result = self.git("checkout", "-q", "-b", "other", cwd=linked)

        self.assertEqual("", result.stdout + result.stderr)
        self.assertFalse((linked / ".env").exists())

    def test_copy_failure_fails_the_hook(self) -> None:
        if os.geteuid() == 0:
            self.skipTest("root ignores file permissions")
        self.include()
        secret = self.primary / ".env"
        secret.chmod(0o000)
        self.addCleanup(secret.chmod, 0o600)
        linked = self.root / "linked"

        result = self.git("worktree", "add", "-q", "--detach", str(linked), check=False)

        self.assertNotEqual(0, result.returncode)
        self.assertIn("worktree-include: could not copy", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_rejects_other_arguments_with_post_checkout(self) -> None:
        result = run(
            str(PROGRAM),
            "--dry-run",
            "--post-checkout",
            "0" * 40,
            "0" * 40,
            "1",
            cwd=self.primary,
            check=False,
        )

        self.assertEqual(2, result.returncode)
        self.assertIn("cannot be combined", result.stderr)


if __name__ == "__main__":
    _ = unittest.main()
