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

A phase is scoped as one independently valuable atomic commit: the smallest cohesive change that can
be reviewed, reverted, explained, and verified on its own. Keep tightly coupled setup, caller
updates, tests, and contract changes together when splitting would add overhead without improving
review or rollback. Apply `references/phase-task-boundary.md` § Phase Size when deciding whether to
split or keep tasks together.

| Form       | Location                      | Heading            | Notes                                                                 |
| ---------- | ----------------------------- | ------------------ | --------------------------------------------------------------------- |
| File-based | Separate `NN-phase-P.md` file | `## Phase P: Name` | Holds required sections and any needed optional phase-local sections. |
