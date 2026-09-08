"""Bounded cooperative locks, never held while waiting for replies."""

import fcntl
import hashlib
import os
import time
from collections.abc import Generator
from contextlib import contextmanager
from pathlib import Path

from .errors import TeamError
from .private_fs import private_directory, private_file


class Locks:
    def __init__(self, root: Path, timeout: float = 5) -> None:
        self.root: Path = root
        self.timeout: float = timeout
        private_directory(root)

    @contextmanager
    def hold(self, key: str) -> Generator[None]:
        path = self.root / (hashlib.sha256(key.encode()).hexdigest() + ".lock")
        descriptor = private_file(path)
        deadline = time.monotonic() + self.timeout
        try:
            while True:
                try:
                    fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    if time.monotonic() >= deadline:
                        raise TeamError(
                            "busy", "Timed out acquiring teammate state lock"
                        ) from None
                    time.sleep(0.02)
            yield
        finally:
            os.close(descriptor)
