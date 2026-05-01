# Phase Implement Brief

## Instructions

You are implementing tasks for a phase of the goal workflow. Read the state file, execute tasks, and
update the state file in real-time.

### Step 1: Load State

Read the state file at the path provided by the orchestrator.

Read these sections:

- `### Context` -- understand the intent and any delegated context
- `### Approach` -- strategy, constraints, and patterns guiding implementation
- `### Tasks` -- pending work items
- `### Issues` -- unresolved problems

Read the AC source file (`.goals/_current/00-main.md`) `## Acceptance Criteria` section for AC text
-- this is used for testability assessment in Step 4.

### Step 2: Handle Open Issues

For each open issue `[ ]` in `### Issues` without a corresponding pending task in `### Tasks`:

- Create a task to fix it `(IN)`, append to `### Tasks`
- Write the update to the state file immediately
- Never leave issues open without a pending task
- Never defer to "tech debt" or "future work" -- if documented, fix now

### Step 3: Execute Tasks

For each pending task `[ ]` in order:

1. Implement the task (write code, tests, etc.)
2. On success: mark as `[x]` in the state file immediately
3. On blocked: mark as `[!]` in the state file with reason, continue to next task:
   `N. [!] Task description — blocked: reason`

Update the state file after each task -- do not batch updates.

### Step 4: Assess Testability

After all tasks complete, for each AC referenced by a `satisfy` task:

- If the AC has a `satisfy` task but no `codify` task, assess testability

**Testability judgment** (use AC text from `.goals/_current/00-main.md`):

- AC describes observable behavior with clear inputs/outputs -- testable
- AC describes internal structure, config, or prose content -- not testable

**If testable**: Create `(ACN, codify)` task in the state file's `### Tasks`, then execute it. **If
not testable**: Annotate the AC directly in the state file's `### Tasks` section by appending a
`(human)` marker to the relevant satisfy task (e.g.,
`N. [x] Task description (ACM, satisfy) (human: reason)`). Also note in the summary.

### Step 5: Return Summary

Return a structured summary:

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

## Task Format

```markdown
### Tasks
1. [ ] Task description
2. [ ] Another task (AC1, satisfy)
3. [ ] Write test for feature (AC1, codify)
4. [ ] Fix race condition (I1)
```

Tasks are a flat numbered list. No groupings or sub-headers.

References:

- `(ACN, satisfy)` - implement behavior for ACN
- `(ACN, codify)` - write test that verifies ACN
- `(IN)` - address issue N

## Task Markers

| Marker | Meaning  |
| ------ | -------- |
| `[ ]`  | Pending  |
| `[x]`  | Complete |
| `[!]`  | Blocked  |

## Rules

- Mark progress in real-time (don't batch updates)
- If blocked, document why and continue
- State file is the single source of truth -- all progress is written there
- **Single-revision invariant**: Never run `jj commit`, `jj new`, or `jj split` during
  implementation. All changes must stay in `@`. The orchestrator owns revision lifecycle — commits
  happen only after verify completes and the phase is approved.
