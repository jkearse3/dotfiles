"""The registry, stem reservations, watch records, and watch lock on disk.

Layout under the state directory:

    stems/<stem>                       one empty file per reserved stem
    parents/<parent>/registry.jsonl    append-only registrations and releases
    parents/<parent>/watch.json        what `watch` recorded per helper block
    parents/<parent>/watch.lock        held by the one running `watch`

Every writer appends one line with a single write, so concurrent `start`,
`resume`, and `release` runs never overwrite each other. Only the lock holder
writes `watch.json`, replacing it whole.
"""

from __future__ import annotations

import fcntl
import json
import os
import tempfile
from dataclasses import asdict, dataclass, field
from pathlib import Path


class StoreError(Exception):
    """State that cannot be read or written."""


@dataclass(frozen=True)
class Registration:
    """One launch of a helper: its first start or a resume."""

    stem: str
    name: str
    harness: str
    block: str
    dir: str
    result: str
    registered_at: float


@dataclass(frozen=True)
class Helper(Registration):
    """A registration with when the parent released it, if it has."""

    released_at: float | None = None

    @property
    def released(self) -> bool:
        return self.released_at is not None


@dataclass
class WatchRecord:
    """What `watch` last saw of one helper block and which lines it printed."""

    status: str | None = None
    updated_at: str | None = None
    reason: str | None = None
    result_done: bool = False
    done_at: float | None = None
    exited: str | None = None
    exited_at: float | None = None


@dataclass
class WatchRecords:
    by_block: dict[str, WatchRecord] = field(default_factory=dict)

    def get(self, block: str) -> WatchRecord:
        return self.by_block.setdefault(block, WatchRecord())

    def peek(self, block: str) -> WatchRecord:
        record = self.by_block.get(block)
        return record if record is not None else WatchRecord()


class Store:
    def __init__(self, root: Path, parent: str) -> None:
        self.root = root
        self.parent = parent
        self.parent_dir = root / "parents" / parent

    def reserve_stem(self, stem: str) -> bool:
        """Reserve STEM for good; False when any parent already holds it."""
        stems = self.root / "stems"
        _make_dirs(stems)
        try:
            os.close(os.open(stems / stem, os.O_CREAT | os.O_EXCL | os.O_WRONLY))
        except FileExistsError:
            return False
        except OSError as error:
            raise StoreError(f"cannot reserve {stem}: {error}") from error
        return True

    def register(self, registration: Registration) -> None:
        self._append({"event": "register", **asdict(registration)})

    def release(self, block: str, at: float) -> None:
        self._append({"event": "release", "block": block, "at": at})

    def helpers(self) -> list[Helper]:
        """Return every registration in order, with when it was released."""
        registrations: list[Registration] = []
        released: dict[str, float] = {}
        path = self.parent_dir / "registry.jsonl"
        try:
            text = path.read_text()
        except FileNotFoundError:
            return []
        except OSError as error:
            raise StoreError(f"cannot read {path}: {error}") from error
        lines = text.split("\n")
        # The last element is empty after a final newline, or a line another
        # process is still appending; either way it is not an entry yet.
        for number, line in enumerate(lines[:-1], 1):
            if line.strip() == "":
                continue
            try:
                event = json.loads(line)
                if event["event"] == "register":
                    del event["event"]
                    registrations.append(Registration(**event))
                elif event["event"] == "release":
                    _ = released.setdefault(event["block"], event["at"])
            except (ValueError, KeyError, TypeError) as error:
                raise StoreError(f"{path}:{number}: unreadable entry: {error}")
        return [
            Helper(**asdict(r), released_at=released.get(r.block))
            for r in registrations
        ]

    def watch_records(self) -> WatchRecords:
        path = self.parent_dir / "watch.json"
        try:
            data = json.loads(path.read_text())
            return WatchRecords(
                {block: WatchRecord(**fields) for block, fields in data.items()}
            )
        except FileNotFoundError:
            return WatchRecords()
        except (OSError, ValueError, TypeError) as error:
            raise StoreError(f"cannot read {path}: {error}") from error

    def save_watch_records(self, records: WatchRecords) -> None:
        _make_dirs(self.parent_dir)
        data = {block: asdict(record) for block, record in records.by_block.items()}
        try:
            with tempfile.NamedTemporaryFile(
                "w", dir=self.parent_dir, prefix=".watch.", delete=False
            ) as file:
                json.dump(data, file)
            os.replace(file.name, self.parent_dir / "watch.json")
        except OSError as error:
            raise StoreError(f"cannot write watch records: {error}") from error

    def try_lock(self) -> WatchLock | None:
        """Take this parent's watch lock, or None while another run holds it.

        The kernel drops the lock when its holder exits, so a crashed run
        never blocks the next one.
        """
        _make_dirs(self.parent_dir)
        path = self.parent_dir / "watch.lock"
        try:
            descriptor = os.open(path, os.O_CREAT | os.O_RDWR)
        except OSError as error:
            raise StoreError(f"cannot open {path}: {error}") from error
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            os.close(descriptor)
            return None
        return WatchLock(descriptor)

    def _append(self, event: dict[str, object]) -> None:
        _make_dirs(self.parent_dir)
        line = (json.dumps(event) + "\n").encode()
        path = self.parent_dir / "registry.jsonl"
        try:
            descriptor = os.open(path, os.O_CREAT | os.O_WRONLY | os.O_APPEND)
            try:
                _ = os.write(descriptor, line)
            finally:
                os.close(descriptor)
        except OSError as error:
            raise StoreError(f"cannot write {path}: {error}") from error


class WatchLock:
    def __init__(self, descriptor: int) -> None:
        self._descriptor: int | None = descriptor

    def release(self) -> None:
        if self._descriptor is not None:
            os.close(self._descriptor)
            self._descriptor = None


def _make_dirs(path: Path) -> None:
    try:
        path.mkdir(parents=True, exist_ok=True)
    except OSError as error:
        raise StoreError(f"cannot create {path}: {error}") from error
