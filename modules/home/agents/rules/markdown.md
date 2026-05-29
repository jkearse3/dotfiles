# Markdown

Rules for agent-authored markdown: docs, skill references, rules files, any `.md` output. Fenced
code blocks and tables follow the rules of the content they carry, not this width cap.

## Width

- Wrap at 100 columns.
- Unbreakable tokens — URLs, file paths, inline code spans — are exceptions: let the line exceed 100
  rather than split the token (splitting hurts readability, search, and copy).
- Prefer rephrasing before overrun: split a sentence, move a long reference to a sub-bullet, or link
  from a brief phrase. Overrun is the last resort.
