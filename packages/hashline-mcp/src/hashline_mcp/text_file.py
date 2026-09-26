"""Byte-faithful text file loading and atomic replacement.

A `TextFile` keeps every line's own terminator, so an edit rewrites only the
lines it touches: mixed line endings, a missing final newline, and a UTF-8 BOM
all survive. Files that are not UTF-8 text are refused rather than transcoded.
"""

import os
import stat
import tempfile
from dataclasses import dataclass
from pathlib import Path

from .errors import ToolError

MAX_FILE_BYTES = 32 * 1024 * 1024
UTF8_BOM = b"\xef\xbb\xbf"


# A file's new lines in order: an int is an existing line, by index, and a
# str is a new line's content.
type Layout = list[int | str]


@dataclass(frozen=True)
class TextFile:
    """Decoded file content.

    `lines` hold content without terminators and `endings` the matching
    terminator (`"\\n"`, `"\\r\\n"`, or `""` for a final line without one), so
    the two lists always have equal, non-zero length. An empty file is one
    empty placeholder line with no terminator (see `is_empty`).
    """

    lines: list[str]
    endings: list[str]
    bom: bool

    @property
    def is_empty(self) -> bool:
        """Whether the file has no content. Its one line is then a placeholder
        with no terminator state to keep: lines written into it all end with
        `newline`."""
        return self.lines == [""] and self.endings == [""]

    @property
    def newline(self) -> str:
        """The terminator given to inserted lines: the file's majority ending."""
        return "\r\n" if self.endings.count("\r\n") > self.endings.count("\n") else "\n"

    def splice(self, splices: list[tuple[int, int, list[str]]]) -> "TextFile":
        """Replace `lines[start:stop]` with `new_lines` for each splice, giving
        new lines `newline` and keeping every untouched line's own terminator,
        then settle as `settle` does. Splices are sorted by position and do
        not overlap."""
        lines: list[str] = []
        endings: list[str] = []
        previous = 0
        for start, stop, new_lines in splices:
            lines += self.lines[previous:start] + new_lines
            endings += self.endings[previous:start] + [self.newline] * len(new_lines)
            previous = stop
        lines += self.lines[previous:]
        endings += self.endings[previous:]
        return self.settle(lines, endings)

    def rearrange(self, layout: "Layout") -> "TextFile":
        """Build the file from `layout`: an int entry is that old line with its
        terminator, and a str entry a new line ending with `newline`. Old
        lines left out are dropped. Settles as `settle` does."""
        lines = [self.lines[entry] if isinstance(entry, int) else entry for entry in layout]
        endings = [
            self.endings[entry] if isinstance(entry, int) else self.newline for entry in layout
        ]
        return self.settle(lines, endings)

    def settle(self, lines: list[str], endings: list[str]) -> "TextFile":
        """Build the successor of this file from edited `lines` and their
        `endings`: a line left without a terminator short of the end gets
        `newline`, the final terminator follows `final_ending`, and carriage
        returns settle as `settle_carriage_returns` does."""
        if len(lines) == 0:
            return TextFile(lines=[""], endings=[""], bom=self.bom)

        endings = [
            ending if ending != "" else self.newline for ending in endings[:-1]
        ] + [self.final_ending(lines)]
        return settle_carriage_returns(lines, endings, self.bom)

    def rewrite(self, changes: dict[int, str]) -> "TextFile":
        """Replace the content of the lines indexed by `changes`, keeping the
        line count and every line's terminator except the final one, which
        `final_ending` settles, and settling carriage returns as
        `settle_carriage_returns` does."""
        lines = [changes.get(index, line) for index, line in enumerate(self.lines)]
        endings = self.endings[:-1] + [self.final_ending(lines)]
        return settle_carriage_returns(lines, endings, self.bom)

    def final_ending(self, lines: list[str]) -> str:
        """The terminator for the last of `lines`, the edited successor of this
        file's lines.

        The file's final terminator state is kept, except that an unterminated
        final line must have content unless it is the whole file: an empty one
        would encode to nothing and vanish on the next read. So the final line
        gets `newline` instead of staying unterminated when it is empty, or
        when this file `is_empty` and its placeholder carried no state.
        """
        kept = self.endings[-1]
        if kept == "" and lines != [""] and (self.is_empty or lines[-1] == ""):
            return self.newline
        return kept

    def encode(self) -> bytes:
        text = "".join(line + ending for line, ending in zip(self.lines, self.endings))
        return (UTF8_BOM if self.bom else b"") + text.encode("utf-8")


def settle_carriage_returns(
    lines: list[str], endings: list[str], bom: bool
) -> TextFile:
    """Build a `TextFile` from edited lines, splitting carriage returns as a
    fresh read would.

    A line whose content ends in `"\\r"` and whose terminator is `"\\n"`
    encodes as a CRLF line, so its trailing `"\\r"` moves into a `"\\r\\n"`
    ending, as `decode_text` would split it. The bytes and the line count are
    unchanged; any other line is kept as given.
    """
    settled_lines = list(lines)
    settled_endings = list(endings)
    for index, (line, ending) in enumerate(zip(lines, endings)):
        if ending == "\n" and line.endswith("\r"):
            settled_lines[index] = line[:-1]
            settled_endings[index] = "\r\n"
    return TextFile(lines=settled_lines, endings=settled_endings, bom=bom)


@dataclass(frozen=True)
class Fingerprint:
    """Identity of one on-disk version of a file, used to detect outside writes."""

    inode: int
    size: int
    mtime_ns: int
    ctime_ns: int


def fingerprint(path: Path) -> Fingerprint:
    metadata = path.stat()
    return Fingerprint(
        inode=metadata.st_ino,
        size=metadata.st_size,
        mtime_ns=metadata.st_mtime_ns,
        ctime_ns=metadata.st_ctime_ns,
    )


def load_text_file(path: Path) -> tuple[TextFile, Fingerprint]:
    """Read and decode `path`.

    Raises `ToolError` with `E_NOT_FOUND`, `E_NOT_TEXT` (directory, NUL byte,
    or invalid UTF-8), or `E_TOO_LARGE`.
    """
    if not path.exists():
        raise ToolError("E_NOT_FOUND", f"{path} does not exist")
    if not path.is_file():
        raise ToolError("E_NOT_TEXT", f"{path} is not a regular file")

    version = fingerprint(path)
    if version.size > MAX_FILE_BYTES:
        raise ToolError(
            "E_TOO_LARGE",
            f"{path} is {version.size} bytes; the limit is {MAX_FILE_BYTES}",
        )

    data = path.read_bytes()
    if b"\0" in data:
        raise ToolError(
            "E_NOT_TEXT", f"{path} contains NUL bytes; it is binary or UTF-16/32 text"
        )
    return decode_text(data, path), version


def decode_text(data: bytes, path: Path) -> TextFile:
    bom = data.startswith(UTF8_BOM)
    try:
        text = data[len(UTF8_BOM) if bom else 0 :].decode("utf-8")
    except UnicodeDecodeError as error:
        raise ToolError(
            "E_NOT_TEXT", f"{path} is not valid UTF-8 at byte {error.start}"
        ) from None

    # Split on "\n" alone: `str.splitlines` would also break on form feeds,
    # U+2028, and other characters that are ordinary content in source files.
    parts = text.split("\n")
    lines: list[str] = []
    endings: list[str] = []
    for part in parts[:-1]:
        if part.endswith("\r"):
            lines.append(part[:-1])
            endings.append("\r\n")
        else:
            lines.append(part)
            endings.append("\n")
    if parts[-1] != "" or len(lines) == 0:
        lines.append(parts[-1])
        endings.append("")
    return TextFile(lines=lines, endings=endings, bom=bom)


def write_text_file(
    path: Path, content: TextFile, expected: Fingerprint
) -> Fingerprint:
    """Atomically replace `path` with `content`, keeping its permission bits.

    Refuses with `E_FILE_CHANGED` when the file no longer matches `expected`,
    so a write never clobbers a change made since the content was loaded.
    `path` must already be resolved, so a symlink is followed rather than
    replaced.
    """
    if fingerprint(path) != expected:
        raise ToolError(
            "E_FILE_CHANGED", f"{path} changed on disk during the edit; retry"
        )

    mode = stat.S_IMODE(path.stat().st_mode)
    descriptor, temporary = tempfile.mkstemp(
        dir=path.parent, prefix=f".{path.name}.", suffix=".hashline"
    )
    try:
        with os.fdopen(descriptor, "wb") as handle:
            _ = handle.write(content.encode())
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    except BaseException:
        Path(temporary).unlink(missing_ok=True)
        raise
    return fingerprint(path)
