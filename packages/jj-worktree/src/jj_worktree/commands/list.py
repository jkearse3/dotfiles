from pathlib import Path

from ..core import managed, repository
from ..core.managed import WorktreeRecord
from ..core.repository import MANAGED_ROOT_NAME


def list_worktrees(
    names: list[str] | None = None, start: Path | None = None
) -> list[WorktreeRecord]:
    repo = repository.discover_repository(start)
    worktrees = repository.parse_worktrees(repo.current)
    if names:
        selected = names
    else:
        selected: list[str] = []
        root = repo.primary / MANAGED_ROOT_NAME
        for worktree in worktrees:
            try:
                relative = worktree.path.relative_to(root)
            except ValueError:
                continue
            if len(relative.parts) == 1:
                selected.append(relative.name)
    return [managed.record(repo, name, worktrees) for name in selected]
