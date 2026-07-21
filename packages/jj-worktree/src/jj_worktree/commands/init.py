from pathlib import Path

from ..core import exclude, repository


def initialize(start: Path | None = None) -> Path:
    return exclude.initialize_repository(repository.discover_repository(start))
