# Phase Implement Brief

Implement tasks for a phase of the objective workflow: execute pending tasks and update the state
file in real-time.

## References

- `references/contracts.md` — file conventions and § Invariants (the single-revision rule and
  caller-token preservation).

## Steps

1. Load state. Read the state file at the path provided by the orchestrator:
   - `### Context` — intent and any delegated context.
   - `### Approach` — strategy, constraints, and patterns guiding implementation.
   - `### Tasks` — pending work items.
   - `### Issues` — unresolved problems.

   Read the AC source file (`.objectives/_current/00-main.md`) `## Acceptance Criteria` section for
   AC text — used for testability assessment in Step 4.

2. Handle open issues. For each open issue `[ ]` in `### Issues` without a corresponding pending
   task in `### Tasks`:
   - Create a task to fix it `(IN)`, append to `### Tasks`, and write the update immediately.
   - Never leave issues open without a pending task.
   - Never defer to "tech debt" or "future work" — if documented, fix now.

3. Execute tasks. For each pending task `[ ]` in order:
   1. Implement the task (write code, tests, etc.).
   2. On success: mark `[x]` in the state file immediately.
   3. On blocked: mark `[!]` with reason, then continue to the next task:
      `N. [!] Task description — blocked: reason`.

   Update the state file after each task — do not batch updates.

4. Assess testability. After all tasks complete, for each AC referenced by a `satisfy` task (not
   `enhance` — those target already-validated ACs and don't need codify):
   - If the AC has a `satisfy` task but no `codify` task, assess testability using AC text from
     `.objectives/_current/00-main.md`:
     - AC describes observable behavior with clear inputs/outputs — testable.
     - AC describes internal structure, config, or prose content — not testable.
   - **If testable**: create a `(ACN, codify)` task in `### Tasks`, then execute it.
   - **If not testable**: annotate the AC directly in `### Tasks` by appending a `(human)` marker to
     the relevant satisfy task (e.g., `N. [x] Task description (ACM, satisfy) (human: reason)`).
     Also note it in the summary.

5. Return summary. Return the `## Result: Implementation Summary` block (see Contracts).

## Contracts

### Result Block

Headings and fields are caller-parsed — do not rename or reorder.

```
## Result: Implementation Summary

### Tasks Created
- [list of reactively created tasks, or "None"]

### Tasks Completed
- [list of completed tasks]

### Tasks Blocked
- [list of blocked tasks with reasons, or "None"]

### Testability Assessments
- [list of ACs assessed, codify tasks created or marked human, or "None"]

### Concerns
- [any issues requiring user input, or "None"]
```

### Task Format

```markdown
### Tasks
1. [ ] Task description
2. [ ] Another task (AC1, satisfy)
3. [ ] Write test for feature (AC1, codify)
4. [ ] Fix race condition (I1)
```

Tasks are a flat numbered list. No groupings or sub-headers.

### Task Annotations

- `(ACN, satisfy)` — implement behavior for ACN.
- `(ACN, enhance)` — improve or refine an already-satisfied ACN.
- `(ACN, codify)` — write test that verifies ACN.
- `(IN)` — address issue N.

### Task Markers

| Marker | Meaning  |
| ------ | -------- |
| `[ ]`  | Pending  |
| `[x]`  | Complete |
| `[!]`  | Blocked  |

### Rules

- Mark progress in real-time (don't batch updates).
- If blocked, document why and continue.
- State file is the single source of truth — all progress is written there.
- **Single-revision invariant** (`references/contracts.md` § Invariants): never run `jj commit`,
  `jj new`, or `jj split` during implementation. All changes must stay in `@`. The orchestrator owns
  revision lifecycle — commits happen only after verify completes and the phase is approved.
