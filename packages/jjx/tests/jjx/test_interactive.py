from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import override


def run(
    *command: str,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command, cwd=cwd, env=env, check=check, capture_output=True, text=True
    )


class InteractiveIntegrationTests(unittest.TestCase):
    """Exercise interactive workflows with fzf's deterministic filter mode."""

    temporary: tempfile.TemporaryDirectory[str]
    root: Path
    home: Path
    environment: dict[str, str]
    repository: Path

    @override
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.environment = os.environ.copy()
        self.environment["HOME"] = str(self.home)
        self.environment["GIT_CONFIG_NOSYSTEM"] = "1"
        self.environment["GIT_CONFIG_GLOBAL"] = str(self.root / "gitconfig")
        source_root = str(Path(__file__).resolve().parents[2] / "src")
        inherited_pythonpath = self.environment.get("PYTHONPATH")
        self.environment["PYTHONPATH"] = (
            source_root
            if inherited_pythonpath is None or inherited_pythonpath == ""
            else f"{source_root}{os.pathsep}{inherited_pythonpath}"
        )

    def jjx(
        self, *arguments: str, filter_expression: str
    ) -> subprocess.CompletedProcess[str]:
        environment = self.environment | {
            "FZF_DEFAULT_OPTS": f"--filter={filter_expression}"
        }
        return run(
            sys.executable,
            "-m",
            "jjx",
            *arguments,
            cwd=self.repository,
            env=environment,
            check=False,
        )

    def initialize_repository(self) -> None:
        self.repository = self.root / "repository"
        _ = run("git", "init", "-b", "main", str(self.repository), env=self.environment)
        _ = run(
            "git",
            "-C",
            str(self.repository),
            "config",
            "user.name",
            "Test User",
            env=self.environment,
        )
        _ = run(
            "git",
            "-C",
            str(self.repository),
            "config",
            "user.email",
            "test@example.com",
            env=self.environment,
        )
        _ = (self.repository / "tracked").write_text("initial\n")
        _ = run(
            "git", "-C", str(self.repository), "add", "tracked", env=self.environment
        )
        _ = run(
            "git",
            "-C",
            str(self.repository),
            "commit",
            "-m",
            "initial",
            env=self.environment,
        )

    def test_push_selects_multiple_bookmarks_and_rejects_selector_options(self) -> None:
        self.initialize_repository()
        remote = self.root / "remote.git"
        _ = run(
            "git", "init", "--bare", "-b", "main", str(remote), env=self.environment
        )
        for bookmark in ("feature-one", 'feature-"two', "feature-é"):
            _ = run(
                "git",
                "-C",
                str(self.repository),
                "branch",
                bookmark,
                env=self.environment,
            )
        _ = run(
            "git",
            "-C",
            str(self.repository),
            "remote",
            "add",
            "origin",
            str(remote),
            env=self.environment,
        )
        _ = run(
            "jj",
            "git",
            "init",
            "--colocate",
            str(self.repository),
            env=self.environment,
        )

        rejected = self.jjx("bookmark", "push", "--all", filter_expression="feature-")
        self.assertEqual(2, rejected.returncode)
        self.assertIn("push selector option is not supported: --all", rejected.stderr)

        pushed = self.jjx(
            "bookmark", "push", "--remote", "origin", filter_expression="feature-"
        )
        self.assertEqual(0, pushed.returncode, pushed.stderr)
        references = run(
            "git",
            f"--git-dir={remote}",
            "for-each-ref",
            "--format=%(refname:short)",
            "refs/heads",
            env=self.environment,
        ).stdout.splitlines()
        self.assertEqual(
            ['feature-"two', "feature-one", "feature-é"], sorted(references)
        )

    def test_rebase_handles_bookmark_names_that_require_revset_quoting(self) -> None:
        self.initialize_repository()
        for bookmark, filename in (
            ("feature-one", "one"),
            ("release)1", "release-close"),
            ('release"1', "release-quote"),
        ):
            _ = run(
                "git",
                "-C",
                str(self.repository),
                "checkout",
                "-q",
                "-b",
                bookmark,
                "main",
                env=self.environment,
            )
            _ = (self.repository / filename).write_text(f"{filename}\n")
            _ = run(
                "git", "-C", str(self.repository), "add", filename, env=self.environment
            )
            _ = run(
                "git",
                "-C",
                str(self.repository),
                "commit",
                "-m",
                filename,
                env=self.environment,
            )
        _ = run(
            "git",
            "-C",
            str(self.repository),
            "checkout",
            "-q",
            "main",
            env=self.environment,
        )
        _ = (self.repository / "advanced").write_text("advanced\n")
        _ = run(
            "git", "-C", str(self.repository), "add", "advanced", env=self.environment
        )
        _ = run(
            "git",
            "-C",
            str(self.repository),
            "commit",
            "-m",
            "advanced",
            env=self.environment,
        )
        _ = run(
            "jj",
            "git",
            "init",
            "--colocate",
            str(self.repository),
            env=self.environment,
        )

        rebased = self.jjx("bookmark", "rebase", "main", filter_expression="release")
        self.assertEqual(0, rebased.returncode, rebased.stderr)
        for bookmark in ("release)1", 'release"1'):
            with self.subTest(bookmark=bookmark):
                revset = f"bookmarks(exact:{json.dumps(bookmark)})-"
                parent = run(
                    "jj",
                    "-R",
                    str(self.repository),
                    "log",
                    "--no-graph",
                    "-r",
                    revset,
                    "-T",
                    "local_bookmarks",
                    env=self.environment,
                ).stdout.strip()
                self.assertEqual("main", parent)
