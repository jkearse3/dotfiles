# Phases

Phase index format, content resolution, and per-phase section structure.

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

## Phase Resolution

Centralized pattern for locating phase content. All procedures and briefs use this instead of
assuming a phase file path directly.

1. Read the `## Phases` index in `00-main.md`.
2. Index entry contains a markdown link (e.g., `[Phase Name](./02-phase-1.md)`) → phase content is
   in that linked file.

## Phase Sections

Each phase contains these required sections:

- `### Context` — what/why: intent and motivation for this phase.
- `### Approach` — strategy, architectural notes, constraints.
- `### Tasks` — flat numbered list.
- `### Issues` — flat numbered list.

Optional phase-local sections may be added when needed:

- `### Decisions` — phase-local decisions from phase interrogation. Objective-wide decisions remain
  in `00-main.md` under `## Research > ### Decisions`.
- `### Continuation` — phase-local resume state for unresolved follow-up, route changes, or
  compaction recovery. Objective-wide state remains in `00-main.md`.

### Continuation Schema

When present, `### Continuation` uses this minimal schema:

```markdown
### Continuation

Status: <status token>
Source: <where the continuation was created>
Route: <procedure or step to resume>
Summary: <one-paragraph resume context>
Clear when: <condition that makes the next resume point unambiguous>

#### Payload

[Optional structured details needed by the routed procedure]
```

`#### Payload` is optional. Omit it when the fixed labels provide enough resume context.

A phase is scoped as a single commit of work. It is atomic when all its tasks serve one cohesive
change — if any task could land independently, it belongs in its own phase.

| Form       | Location                      | Heading            | Notes                                                                 |
| ---------- | ----------------------------- | ------------------ | --------------------------------------------------------------------- |
| File-based | Separate `NN-phase-P.md` file | `## Phase P: Name` | Holds required sections and any needed optional phase-local sections. |
