# Phase Implement Brief

Implement tasks for a phase of the objective workflow: execute pending tasks and update the state
file in real-time.

## References

- `references/contracts.md` — file conventions and § Invariants (the single-revision rule and
  caller-token preservation).
- `references/templates.md` — § Phase Task Boundary for task validity.

## Write Permissions

- Write the phase file at the provided path (update task markers and append tasks)

## Steps

1. Load state. Apply `references/contracts.md` § Load Phase Subagent State. Use AC text for
   testability assessment in Step 4.

2. Handle open issues. For each open issue `[ ]` in `### Issues` without a corresponding pending
   task in `### Tasks`:
   - Create a task to fix it `(IN)` only when the task satisfies `references/templates.md` § Phase
     Task Boundary. Append it to `### Tasks`, and write the update immediately.
   - If the required fix would violate the boundary, leave the issue open and report it in
     `### Concerns` instead of creating a task.
   - Never leave issues open without a pending task unless the boundary prevents creating a valid
     task; report any such issue in `### Concerns`.
   - Never defer to "tech debt" or "future work" — if documented, fix now.

3. Execute tasks. For each pending task `[ ]` in order:
   1. Check the task against `references/templates.md` § Phase Task Boundary. If it violates the
      boundary, mark `[!]` with reason and do not execute it.
   2. Implement the task (write code, tests, etc.).
   3. On success: mark `[x]` in the state file immediately.
   4. On blocked: mark `[!]` with reason, then continue to the next task:
      `N. [!] Task description — blocked: reason`.

   Update the state file after each task — do not batch updates.

4. Assess testability. After all tasks complete, for each AC referenced by a `satisfy` task (not
   `enhance` — those target already-validated ACs and don't need codify):
   - If the AC has a `satisfy` task but no `codify` task, assess testability using AC text from
     `.objectives/_current/00-main.md`:
     - AC describes observable behavior with clear inputs/outputs — testable.
     - AC describes internal structure, config, or prose content — not testable.
   - **If testable**: create a `(ACN, codify)` task in `### Tasks` only when it satisfies
     `references/templates.md` § Phase Task Boundary, then execute it. If the codify task would
     violate the boundary, mark the relevant satisfy task with
     `(human: codify task violates phase task boundary)` and note it in the summary.
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
- **Phase Task Boundary**: never execute a task that violates `references/templates.md` § Phase Task
  Boundary. Mark it `[!]` with a reason instead.
- **Single-revision invariant** (`references/contracts.md` § Invariants): all phase changes must
  stay in `@` during implementation. The orchestrator owns revision lifecycle — commits happen only
  after verify completes and the phase is approved.
