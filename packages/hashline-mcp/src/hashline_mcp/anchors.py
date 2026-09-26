"""Session-scoped anchor identity for the lines of tracked files.

An anchor is a short lowercase string naming one line of one file for the life
of the server process. Lines keep their anchors across edits made through this
server, and across outside changes wherever the line is provably the same line,
so the model can chain edits without re-reading. A line gets a fresh anchor
whenever its identity is uncertain; a retired anchor is never reassigned, so a
stale anchor fails instead of landing on another line.

The store also records which anchors have been shown to the model ("served").
Edits may only name served lines, so the model never edits a line it has not
seen in its current form. A range between two served lines may also cover lines
never shown, but not lines that changed on disk ("changed outside"), whose
content the model may believe is something else.
"""

import bisect
import hashlib
import random
import string
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

from .text_file import (
    Fingerprint,
    Layout,
    TextFile,
    fingerprint,
    load_text_file,
    write_text_file,
)

ANCHOR_ALPHABET = string.ascii_lowercase
MIN_ANCHOR_LENGTH = 3

# `align_lines` scans at most this many times the combined line count.
ALIGNMENT_WORK_FACTOR = 8


@dataclass
class TrackedFile:
    """One file's current content with an anchor per line.

    `retired` maps anchors that no longer exist to the line index where they
    were last seen, so a stale anchor can be answered with nearby rows.
    `changed_outside` holds the unserved anchors of lines that an outside
    change created or moved past, which a range edit must show again.
    """

    path: Path
    content: TextFile
    anchors: list[str]
    version: Fingerprint
    served: set[str] = field(default_factory=set)
    retired: dict[str, int] = field(default_factory=dict)
    changed_outside: set[str] = field(default_factory=set)
    positions: dict[str, int] = field(init=False)

    def __post_init__(self) -> None:
        self.positions = {anchor: index for index, anchor in enumerate(self.anchors)}

    def row(self, index: int) -> tuple[str, str]:
        return self.anchors[index], self.content.lines[index]


class AnchorStore:
    """All tracked files of one server process, keyed by resolved path.

    Not thread-safe; the server handles one request at a time.
    """

    def __init__(self, rng: random.Random | None = None) -> None:
        self.files: dict[Path, TrackedFile] = {}
        self.rng = rng if rng is not None else random.Random()

    def sync(self, path: Path) -> TrackedFile:
        """Return `path`'s tracked state, reloading it if the file changed on disk.

        Raises `ToolError` when the file cannot be loaded as text.
        """
        tracked = self.files.get(path)
        if (
            tracked is not None
            and path.is_file()
            and fingerprint(path) == tracked.version
        ):
            return tracked

        content, version = load_text_file(path)
        if tracked is None:
            # Seeding from the path and content gives an unchanged file the same
            # anchors in every server process, so anchors from before a server
            # restart still name the lines they named.
            seed = hashlib.sha256(bytes(path) + b"\0" + content.encode()).digest()
            tracked = TrackedFile(
                path=path,
                content=content,
                anchors=self.allocate(len(content.lines), set(), random.Random(seed)),
                version=version,
            )
        else:
            tracked = self.realign(tracked, content, version)
        self.files[path] = tracked
        return tracked

    def commit(
        self, tracked: TrackedFile, start: int, stop: int, new_lines: list[str]
    ) -> TrackedFile:
        """Write `lines[start:stop]` replaced by `new_lines` and re-anchor.

        See `commit_splices`.
        """
        return self.commit_splices(tracked, [(start, stop, new_lines)])

    def commit_splices(
        self, tracked: TrackedFile, splices: list[tuple[int, int, list[str]]]
    ) -> TrackedFile:
        """Write each `(start, stop, new_lines)` splice in one write and re-anchor.

        Splices index `tracked` as it is, are sorted by position, and do not
        overlap. Untouched lines keep their anchors; inserted lines get fresh,
        unserved anchors. Raises `ToolError` (`E_FILE_CHANGED`) if the file
        changed since `tracked` was synced.
        """
        content = tracked.content.splice(splices)
        version = write_text_file(tracked.path, content, tracked.version)

        taken = set(tracked.anchors) | set(tracked.retired)
        fresh = iter(self.allocate(sum(len(new) for _, _, new in splices), taken))
        anchors: list[str] = []
        removed: dict[str, int] = {}
        previous = 0
        for start, stop, new_lines in splices:
            anchors += tracked.anchors[previous:start]
            removed.update((anchor, len(anchors)) for anchor in tracked.anchors[start:stop])
            anchors += [next(fresh) for _ in new_lines]
            previous = stop
        anchors += tracked.anchors[previous:]
        if len(anchors) == 0:
            # Deleting every line leaves the one empty line of an empty file.
            anchors = self.allocate(1, taken)

        updated = TrackedFile(
            path=tracked.path,
            content=content,
            anchors=anchors,
            version=version,
            served=tracked.served - removed.keys(),
            retired={**tracked.retired, **removed},
            changed_outside=tracked.changed_outside - removed.keys(),
        )
        self.files[tracked.path] = updated
        return updated

    def commit_layout(self, tracked: TrackedFile, layout: Layout) -> TrackedFile:
        """Write the file as `layout` describes (see `TextFile.rearrange`).

        Existing lines keep their anchors, served state, and terminators, in
        whatever order; new lines get fresh, unserved anchors; lines left out
        are retired. Raises `ToolError` (`E_FILE_CHANGED`) if the file changed
        since `tracked` was synced.
        """
        content = tracked.content.rearrange(layout)
        version = write_text_file(tracked.path, content, tracked.version)

        taken = set(tracked.anchors) | set(tracked.retired)
        fresh = iter(self.allocate(sum(isinstance(entry, str) for entry in layout), taken))
        anchors = [
            tracked.anchors[entry] if isinstance(entry, int) else next(fresh) for entry in layout
        ]
        kept = {entry for entry in layout if isinstance(entry, int)}
        removed = {
            anchor: min(index, len(anchors))
            for index, anchor in enumerate(tracked.anchors)
            if index not in kept
        }
        if len(anchors) == 0:
            # Removing every line leaves the one empty line of an empty file.
            anchors = self.allocate(1, taken)

        updated = TrackedFile(
            path=tracked.path,
            content=content,
            anchors=anchors,
            version=version,
            served=tracked.served - removed.keys(),
            retired={**tracked.retired, **removed},
            changed_outside=tracked.changed_outside - removed.keys(),
        )
        self.files[tracked.path] = updated
        return updated

    def commit_rewrite(
        self, tracked: TrackedFile, changes: dict[int, str]
    ) -> TrackedFile:
        """Write the lines indexed by `changes` with new content in one write.

        The line count is unchanged. Rewritten lines get fresh, unserved
        anchors and every other line keeps its own. Raises `ToolError`
        (`E_FILE_CHANGED`) if the file changed since `tracked` was synced.
        """
        content = tracked.content.rewrite(changes)
        version = write_text_file(tracked.path, content, tracked.version)

        indexes = sorted(changes)
        removed = [tracked.anchors[index] for index in indexes]
        taken = set(tracked.anchors) | set(tracked.retired)
        anchors = list(tracked.anchors)
        for index, anchor in zip(indexes, self.allocate(len(indexes), taken)):
            anchors[index] = anchor

        retired = {**tracked.retired, **dict(zip(removed, indexes))}
        updated = TrackedFile(
            path=tracked.path,
            content=content,
            anchors=anchors,
            version=version,
            served=tracked.served - set(removed),
            retired=retired,
            changed_outside=tracked.changed_outside - set(removed),
        )
        self.files[tracked.path] = updated
        return updated

    def realign(
        self, old: TrackedFile, content: TextFile, version: Fingerprint
    ) -> TrackedFile:
        """Carry anchors from `old` onto content changed outside this server."""
        carried, retired_at = carry_anchors(
            old.content.lines, old.anchors, content.lines
        )

        taken = set(old.anchors) | set(old.retired)
        fresh = iter(self.allocate(carried.count(None), taken))
        anchors = [anchor if anchor is not None else next(fresh) for anchor in carried]
        created = {
            anchor for anchor, carried_anchor in zip(anchors, carried) if carried_anchor is None
        }
        kept = set(anchors)

        # Lines removed from inside a range leave both ends of the range in
        # place. Un-serving the line after each removed run makes any range
        # spanning the gap re-show its rows before replacing them; otherwise the
        # edit would silently restore the removed lines.
        after_gap = {
            old.anchors[index + 1]
            for index, anchor in enumerate(old.anchors[:-1])
            if anchor not in kept and old.anchors[index + 1] in kept
        }

        return TrackedFile(
            path=old.path,
            content=content,
            anchors=anchors,
            version=version,
            served=(old.served & kept) - after_gap,
            retired={**old.retired, **retired_at},
            changed_outside=(old.changed_outside & kept) | after_gap | created,
        )

    def allocate(
        self, count: int, taken: set[str], rng: random.Random | None = None
    ) -> list[str]:
        """Return `count` distinct anchors outside `taken`, drawn from `rng`
        (default: the store's generator).

        Anchors use the fewest letters (at least three) whose space stays at
        most half full, keeping random allocation fast.
        """
        length = MIN_ANCHOR_LENGTH
        while len(taken) + count > len(ANCHOR_ALPHABET) ** length // 2:
            length += 1

        source = rng if rng is not None else self.rng
        allocated: list[str] = []
        used = set(taken)
        while len(allocated) < count:
            anchor = "".join(source.choices(ANCHOR_ALPHABET, k=length))
            if anchor not in used:
                used.add(anchor)
                allocated.append(anchor)
        return allocated


def carry_anchors(
    old_lines: list[str], old_anchors: list[str], new_lines: list[str]
) -> tuple[list[str | None], dict[str, int]]:
    """Map each new line to the anchor of the old line it provably is, or None.

    Returns the per-line anchors and, for each dropped anchor, the new line
    index nearest its old position. Lines are paired by patience alignment
    (see `align_lines`), so a repeated line such as `}` only keeps its anchor
    when a unique neighbor pins its position.
    """
    carried: list[str | None] = [None] * len(new_lines)
    for old_index, new_index in align_lines(old_lines, new_lines):
        carried[new_index] = old_anchors[old_index]

    kept = {anchor for anchor in carried if anchor is not None}
    last_line = max(len(new_lines) - 1, 0)
    retired_at = {
        anchor: min(index, last_line)
        for index, anchor in enumerate(old_anchors)
        if anchor not in kept
    }
    return carried, retired_at


def align_lines(old: list[str], new: list[str]) -> list[tuple[int, int]]:
    """Pair old and new line indexes that hold the same line (patience diff).

    Each window first pairs its identical leading and trailing lines. The
    rest is split at lines that occur exactly once in the window on both
    sides and appear in the same order, and each gap between those pairs is
    aligned the same way. Lines never pinned by a unique match or an
    identical run next to one stay unpaired. Work is capped at
    `ALIGNMENT_WORK_FACTOR` times the input size; windows left when the cap
    is reached stay unpaired, which only costs fresh anchors.
    """
    pairs: list[tuple[int, int]] = []
    windows = [(0, len(old), 0, len(new))]
    budget = ALIGNMENT_WORK_FACTOR * (len(old) + len(new))
    while len(windows) > 0:
        old_start, old_stop, new_start, new_stop = windows.pop()
        while (
            old_start < old_stop
            and new_start < new_stop
            and old[old_start] == new[new_start]
        ):
            pairs.append((old_start, new_start))
            old_start += 1
            new_start += 1
        while (
            old_start < old_stop
            and new_start < new_stop
            and old[old_stop - 1] == new[new_stop - 1]
        ):
            pairs.append((old_stop - 1, new_stop - 1))
            old_stop -= 1
            new_stop -= 1
        if old_start == old_stop or new_start == new_stop:
            continue
        # Nested windows can each yield one pin, so scanning every window in
        # full would be quadratic on adversarial input.
        budget -= (old_stop - old_start) + (new_stop - new_start)
        if budget < 0:
            break

        old_counts = Counter(old[old_start:old_stop])
        new_counts = Counter(new[new_start:new_stop])
        unique_new = {
            new[index]: index
            for index in range(new_start, new_stop)
            if new_counts[new[index]] == 1
        }
        candidates = [
            (index, unique_new[old[index]])
            for index in range(old_start, old_stop)
            if old_counts[old[index]] == 1 and old[index] in unique_new
        ]

        previous_old, previous_new = old_start, new_start
        for old_index, new_index in longest_increasing_run(candidates):
            pairs.append((old_index, new_index))
            windows.append((previous_old, old_index, previous_new, new_index))
            previous_old, previous_new = old_index + 1, new_index + 1
        if previous_old != old_start:
            windows.append((previous_old, old_stop, previous_new, new_stop))
    return pairs


def longest_increasing_run(pairs: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """Return the longest subsequence of `pairs` (sorted by first index) whose
    second indexes increase, in O(n log n)."""
    tails: list[int] = []
    tail_values: list[int] = []
    previous: list[int] = [-1] * len(pairs)
    for position, (_, new_index) in enumerate(pairs):
        slot = bisect.bisect_left(tail_values, new_index)
        if slot > 0:
            previous[position] = tails[slot - 1]
        if slot == len(tails):
            tails.append(position)
            tail_values.append(new_index)
        else:
            tails[slot] = position
            tail_values[slot] = new_index

    run: list[tuple[int, int]] = []
    position = tails[-1] if len(tails) > 0 else -1
    while position != -1:
        run.append(pairs[position])
        position = previous[position]
    run.reverse()
    return run
