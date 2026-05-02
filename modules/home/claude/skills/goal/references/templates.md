# Templates

## New Goal

When creating, generate:

**00-main.md**:

```markdown
## Context

[Why this goal exists]

## Research

### Findings

### Decisions

### Questions

### Assumptions

## Acceptance Criteria

[No ACs yet - define with /goal spec when ready]

## Approach

[No approach yet - define with /goal spec after ACs are set]

## Phases

[No phases yet - scope with /goal phase-scope when ready to implement]
```

## New Phase

Create a numbered phase file and add a linked index entry in `00-main.md`.

### Compute phase-file inputs

Before dispatch, resolve the four values that identify the phase file. Orchestrators that dispatch
the scoping subagent (`procedures/phase-scope.md`, `procedures/phase-iterate.md`) compute these and
pass them in the prompt:

- Resolve `goal_dir`: absolute path of `.goals/_current` (resolve the symlink)
- Compute `P`: highest phase number in `## Phases` index + 1
- Compute `NN`: highest `NN-` prefix in `goal_dir` + 1 (zero-padded to two digits)
- Build absolute path: `<goal_dir>/NN-phase-P.md`

With the inputs resolved above, the remaining steps write the phase file and register it in
`00-main.md`.

**Step 1**: Create `NN-phase-P.md` at the computed absolute path:

```markdown
## Phase P: Phase Name

### Context

### Approach

[Strategy and architectural notes for this phase]

### Tasks
1. [ ] Define scope

### Issues
```

**Step 2**: Add a linked index entry in the `## Phases` section of `00-main.md`:

```markdown
P. [ ] [Phase Name](./NN-phase-P.md) *
```

Move `*` from the previously focused phase to the new entry.
