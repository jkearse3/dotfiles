from pathlib import Path

from ..core import managed, repository
from ..core.process import WorktreeError


def worktree_path(name: str, start: Path | None = None) -> Path:
    managed.validate_name(name)
    repo = repository.discover_repository(start)
    item = managed.record(repo, name)
    if item.status != "ok" or item.path is None:
        raise WorktreeError(f"worktree {name!r} is {item.status}")
    return item.path
