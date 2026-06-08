# Phase Sections

Required and optional section structure for phase files.

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

A phase is scoped as a single commit of work. It is atomic when all its tasks serve one cohesive
change — if any task could land independently, it belongs in its own phase.

| Form       | Location                      | Heading            | Notes                                                                 |
| ---------- | ----------------------------- | ------------------ | --------------------------------------------------------------------- |
| File-based | Separate `NN-phase-P.md` file | `## Phase P: Name` | Holds required sections and any needed optional phase-local sections. |
