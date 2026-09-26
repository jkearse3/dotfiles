"""The file report that ends every edit result.

After a write, the model would otherwise spend a turn checking what the edit
left behind: line endings, the final newline, or a BOM. One `File:` line
states all of it, the same way for every text file.
"""

from .anchors import TrackedFile


def file_report(tracked: TrackedFile) -> str:
    """One line describing `tracked` as written: its line terminators, whether
    it ends in a newline, and whether it starts with a UTF-8 BOM."""
    content = tracked.content
    crlf = content.endings.count("\r\n")
    lf = content.endings.count("\n")
    if crlf > 0 and lf > 0:
        parts = [f"mixed line endings ({crlf} CRLF, {lf} LF)"]
    elif crlf > 0:
        parts = ["CRLF line endings"]
    else:
        parts = ["LF line endings"]
    parts.append("final newline" if content.endings[-1] != "" else "no final newline")
    if content.bom:
        parts.append("UTF-8 BOM")
    return "File: " + ", ".join(parts) + "."
