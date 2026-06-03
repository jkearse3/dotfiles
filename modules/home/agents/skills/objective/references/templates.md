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

### Compute phase-file inputs

Resolve these before dispatching the scoping subagent:

- Resolve `objective_dir`: absolute path of `.objectives/_current` (resolve the symlink)
- Compute `P`: highest phase number in `## Phases` index + 1
- Compute `NN`: highest `NN-` prefix in `objective_dir` + 1 (zero-padded to two digits)
- Build absolute path: `<objective_dir>/NN-phase-P.md`

Use these values to write the phase file and register it in `00-main.md`.

1. Create `NN-phase-P.md` at the computed absolute path.

```markdown
## Phase P: Phase Name

### Context

### Approach

[Strategy and architectural notes for this phase]

### Tasks
1. [ ] Define scope

### Issues
```

2. Add a linked index entry in `00-main.md` under `## Phases`.

```markdown
P. [ ] [Phase Name](./NN-phase-P.md) *
```

3. Move `*` from the previously focused phase to the new entry.

## Contracts

- `00-main.md` remains the objective index.
- Phase files contain only the phase content; registration happens in `00-main.md`.
- New phase templates do not include empty optional sections. Add `### Decisions` or
  `### Continuation` only when phase-local content exists.
- Phase-file input computation is shared by all auto-scope callers.
