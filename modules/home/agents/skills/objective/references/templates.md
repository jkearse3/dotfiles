# Templates

Canonical templates and phase-file creation rules.

## References

- `references/contracts.md` — file conventions and shared invariants.

## New Objective

Generate `00-main.md` with this content:

### `00-main.md`

```markdown
## Context

[Why this objective exists]

## Research

### Findings

### Decisions

### Questions

### Assumptions

## Acceptance Criteria

[No ACs yet - define with /objective spec when ready]

## Approach

[No approach yet - define with /objective spec after ACs are set]

## Phases

[No phases yet - scope with /objective phase-scope when ready to implement]
```

## New Phase

Create a numbered phase file and add a linked index entry in `00-main.md`. New phase files include
only required sections by default. Add optional phase-local sections from `references/phases.md`
only when they have content.

Use this template for new phase files:

```markdown
## Phase P: Phase Name

### Context

[Brief summary of what this phase addresses and why]

### Approach

[Strategy and architectural notes]

### Tasks
1. [ ] [task description] (AC1, satisfy)
2. [ ] [task description] (AC2, enhance)
3. [ ] [cleanup or refactoring task]

### Issues
```

Task annotations:

- `(ACN, satisfy)` — task directly implements an AC that is not yet satisfied.
- `(ACN, enhance)` — task improves or refines an already-satisfied AC.
- No annotation — task is pure implementation detail: cleanup, refactoring, or tooling.

### Phase Task Boundary

During a phase, implementation and verification operate on the current working-copy revision `@`.
All phase changes must remain in `@` until `phase-iterate` reaches its review/commit step.

Phase tasks must describe implementation, validation, cleanup, issue follow-up, or phase-relevant
investigation work. They must not ask agents to run VCS lifecycle operations that move work out of
`@`, change the current working-copy revision, or make `jj diff` stop representing the complete
phase diff. This includes committing, splitting, squashing, abandoning, rebasing, editing another
revision, creating a new working-copy revision, or checking out/switching revisions.

Phase tasks also must not perform objective lifecycle actions owned by `phase-iterate`, such as
marking phase index entries complete, refreshing objective summaries, routing continuation
lifecycle, or asking the user to review and approve the final diff. Approach or constraint text may
mention lifecycle ownership when it helps explain task boundaries.

### Compute phase-file inputs

Resolve these before dispatching the scoping subagent:

- Resolve `objective_dir`: absolute path of `.objectives/_current` (resolve the symlink)
- Compute `P`: highest phase number in `## Phases` index + 1
- Compute `NN`: highest `NN-` prefix in `objective_dir` + 1 (zero-padded to two digits)
- Build absolute path: `<objective_dir>/NN-phase-P.md`

Use these values to write the phase file and register it in `00-main.md`.

1. Create `NN-phase-P.md` at the computed absolute path using the New Phase template.

2. Add a linked index entry in `00-main.md` under `## Phases`.

```markdown
P. [ ] [Phase Name](./NN-phase-P.md) *
```

3. Move `*` from the previously focused phase to the new entry.

## Contracts

- `00-main.md` remains the objective index.
- Phase files contain only the phase content; registration happens in `00-main.md`.
- Phase tasks satisfy § Phase Task Boundary.
- New phase templates do not include empty optional sections. Add `### Decisions` or
  `### Continuation` only when phase-local content exists.
- Phase-file input computation is shared by all auto-scope callers.
