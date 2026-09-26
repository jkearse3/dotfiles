"""Scoring a finished session's working directory against its task."""

import re
from dataclasses import dataclass
from pathlib import Path

from .tasks import BenchTask, FileTree


@dataclass(frozen=True)
class TaskScore:
    """Whether a session produced its task's expected result.

    `mismatched_paths` lists every path whose content differs from the
    expected tree, including files the session created or deleted.
    `answer_matches` is None for tasks without an expected answer.
    """

    mismatched_paths: list[str]
    answer_matches: bool | None

    @property
    def success(self) -> bool:
        return len(self.mismatched_paths) == 0 and self.answer_matches is not False


def score_task(task: BenchTask, work_dir: Path, final_text: str | None) -> TaskScore:
    actual = read_tree(work_dir)
    mismatched = sorted(
        path
        for path in actual.keys() | task.after.keys()
        if actual.get(path) != task.after.get(path)
    )

    answer_matches: bool | None = None
    if task.answer is not None:
        pattern = rf"(?<!\w){re.escape(task.answer)}(?!\w)"
        answer_matches = final_text is not None and re.search(pattern, final_text) is not None

    return TaskScore(mismatched_paths=mismatched, answer_matches=answer_matches)


# Byproducts of checking an edit, such as running Python on it, that say
# nothing about the edit itself.
IGNORED_NAMES = frozenset({"__pycache__", ".DS_Store"})


def read_tree(root: Path) -> FileTree:
    """Every regular file under `root`, keyed by POSIX path relative to it."""
    tree: FileTree = {}
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        if not IGNORED_NAMES.isdisjoint(relative.parts) or not path.is_file():
            continue
        tree[relative.as_posix()] = path.read_bytes()
    return tree


def write_tree(root: Path, tree: FileTree) -> None:
    for relative, content in tree.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        _ = path.write_bytes(content)
