---
name: iterate
description: >-
  Run or resume a jj-native mutation workflow using `.agent/iterate.md` as the conventional state
  file. Use when changes should continue through implement/verify, review, and optional closeout.
argument-hint: "[desired state]"
---

# Iterate

Run one implement/verify iteration from `<jj-root>/.agent/iterate.md`. The state file is the only
iteration interface; never use chat, worker summaries, commits, or other files as control state.

## Arguments

```
$ARGUMENTS
```

- Empty: resume the conventional state file.
- Non-empty: desired outcome for a new iteration.
- Never treat arguments as state-file paths.

## Rules

- This agent orchestrates only; never run implement or verify inline. In-scope work requests for an
  existing iterate-managed change must route through workers, not inline repo or VCS mutations,
  while an iteration is active, in review, or otherwise awaiting feedback.
- Run one active worker pass at a time: implement, then verify, until blocked, review, or ready for
  finalization.
- Respect host and user approval gates. Host approval applies before state-file edits; activation
  approval is defined in `references/state-file.md`.
- Mutations, including revision lifecycle actions, are allowed only when the approved plan,
  boundaries, current procedure, or finalization candidate authorizes them.

Worker dispatch details live in `references/active-dispatch.md`.

## State Basics

Required sections:

- `## Context`
- `## Research`
- `## Acceptance Criteria`
- `## Approach`
- `## Boundaries`
- `## Tasks`
- `## Issues`

Required control fields:

```text
Status: planning | active | blocked | review | complete | finalized
Next: implement | verify | none
```

## Runbook

1. Resolve workspace with `jj root`; stop if it fails.
2. Resolve state file as `<jj-root>/.agent/iterate.md`.
3. Missing state file: follow `procedures/new-iteration.md`.
4. Existing state file: read fresh; validate required sections and `Status` / `Next` using State
   Basics. Read `references/state-file.md` only when creating or repairing state-file structure,
   applying AC Stability, or checking task traceability.
5. Before following a procedure, read only the files it names for the current step; treat them as
   imported instructions, and do not preload files needed only by dispatched workers.
6. Before routing a non-terminal existing state, disambiguate intent: if the user clearly asks to
   abandon, replace, or do unrelated work, require explicit approval, then follow
   `procedures/new-iteration.md`; if intent is unclear, ask whether to resume, revise, or replace;
   otherwise route normally by status.
7. Combine the current user intent with the state machine's `Status` / `Next`, then route to the
   matching procedure.
8. `Status: planning`: follow `procedures/planning.md`.
9. `Status: active`: follow `procedures/active.md` from `Next`.
10. `Status: blocked`: report blockers from `## Issues` or `## Research` questions, then stop. If
    resolved, update the same file and resume when clear and in bounds.
11. `Status: review`: follow `procedures/review.md`.
12. `Status: complete`: follow `procedures/finalize.md`.
13. `Status: finalized` with a clear new desired outcome: follow `procedures/new-iteration.md`.
14. `Status: finalized` without a clear new desired outcome: ask what new iteration to draft and
    stop.
15. After any procedure that may update the state file, reread the state file and route only from
    the updated `Status:` / `Next:`.
16. When stopped, respond with:
    - State file path.
    - Final `Status` and `Next`.
    - AC completion summary and open issues.
