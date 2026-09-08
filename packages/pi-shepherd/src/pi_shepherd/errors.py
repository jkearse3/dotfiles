"""Stable, non-sensitive application failures; never retain subprocess output."""

from typing import TypeVar

T = TypeVar("T")


class TeamError(Exception):
    def __init__(self, code: str, message: str, *, uncertain: bool = False) -> None:
        super().__init__(message)
        self.code: str = code
        self.message: str = message
        self.uncertain: bool = uncertain


def require(condition: bool, code: str, message: str) -> None:
    if not condition:
        raise TeamError(code, message)


def present(value: T | None) -> T:
    if value is None:
        raise TeamError("unhealthy", "No exact managed target")
    return value
