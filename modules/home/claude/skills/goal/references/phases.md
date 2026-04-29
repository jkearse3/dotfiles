# Phases

## Phase Index

Compact numbered list linking to phase files. Never renumber.

| Marker | Meaning                |
| ------ | ---------------------- |
| `[x]`  | Complete               |
| `[ ]`  | Pending                |
| `[-]`  | Cancelled              |
| `*`    | In focus (exactly one) |

Format: `N. [marker] [Phase Name](./NN-phase-P.md) *`

- `N` is the phase number, `P` in the filename matches it
- `NN` is the sequence number (file creation order in the directory)
- Link target is the phase file (see Phase Resolution for lookup)
- `*` on exactly one phase
- Legacy (no link): `N. [marker] Phase Name *` — phase is inline in `00-main.md`

## Phase Resolution

Centralized pattern for locating phase content. All procedures and briefs use this — never assume
inline or file-based directly.

1. Read the `## Phases` index in `00-main.md`
2. If the index entry contains a markdown link (e.g., `[Phase Name](./02-phase-1.md)`) → phase
   content is in that linked file
3. If the index entry has no link (plain text) → phase is an inline `## Phase N: Name` section in
   `00-main.md` (legacy)

Both formats can coexist in the same goal (e.g., during mid-flight migration). Dropping legacy
support later means removing step 3.

## Phase Sections

Each phase contains only:

- `### Context` - what/why: intent and motivation for this phase
- `### Approach` - strategy, architectural notes, constraints
- `### Tasks` - flat numbered list
- `### Issues` - flat numbered list

No Research in phases — all research lives at goal level under `## Research`.

Each phase is scoped as a single commit of work. A phase is atomic when all its tasks serve one
cohesive change — if any task could land independently without the others, it belongs in its own
phase.

**File-based phases** (new): Content lives in a separate `NN-phase-P.md` file. The top-level heading
is `## Phase P: Name`. The file contains only the phase sections listed above. The `### Context`
section is empty by default; populated with intent and motivation when the phase is scoped.

**Inline phases** (legacy): Content lives as a `## Phase N: Name` section in `00-main.md`.
