# Phase Index

Phase index format and linked phase-file resolution.

## Phase Index

Compact numbered list linking to phase files. Never renumber.

| Marker    | Meaning                |
| --------- | ---------------------- |
| `[x]`     | Complete               |
| `[ ]`     | Pending                |
| `[-]`     | Cancelled              |
| `[focus]` | In focus (exactly one) |

Format: `N. [marker] [Phase Name](./NN-phase-P.md) [focus]`

- `N` is the phase number, `P` in the filename matches it.
- `NN` is the sequence number: file creation order in the objective directory.
- Link target is the phase file.
- `[focus]` marks the focused phase; exactly one phase may be focused.

## Phase Resolution

Centralized pattern for locating phase content. All procedures and briefs use
this instead of assuming a phase file path directly.

1. Read the `## Phases` index in `00-main.md`.
2. Index entry contains a markdown link, for example
   `[Phase Name](./02-phase-1.md)`.
3. Resolve phase content from the linked file.
