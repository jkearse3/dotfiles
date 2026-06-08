# Phase File Template

New phase file structure and task annotations shared by phase-file creation callers.

## New Phase

Create a numbered phase file and add a linked index entry in `00-main.md`. New phase files include
only required sections by default. Add optional phase-local sections from
`references/phase-sections.md` only when they have content.

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

## Contracts

- Phase files contain only the phase content; registration happens in `00-main.md`.
- Phase tasks satisfy `references/phase-task-boundary.md` § Phase Task Boundary.
- New phase templates do not include empty optional sections. Add `### Decisions` or
  `### Continuation` only when phase-local content exists.
