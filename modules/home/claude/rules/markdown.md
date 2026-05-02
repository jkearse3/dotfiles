# Markdown

Rules for agent-authored markdown: goal docs, skill references, rules files, and any other `.md`
output.

## Scope

- Applies to all markdown the agent writes.
- Fenced code blocks and tables follow the rules of the content they carry, not this width cap.

## Width

- Wrap at 100 columns.
- Unbreakable tokens — URLs, file paths, inline code spans — are exceptions. Do not break them to
  fit; let the line exceed 100 rather than split the token. Wrapping a path across lines makes it
  harder to read, search, and copy.
- Prefer rephrasing before accepting overrun. Split a sentence, move the long reference to a
  sub-bullet under a shorter label, or link from a brief phrase. Overrun is the last resort, not the
  default.
