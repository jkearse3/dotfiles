---
name: iterate
description: >-
  Run or resume a jj-native mutation workflow using `.agent/iterate.md` as the conventional state
  file. Use when changes should continue through implement/verify, review, and optional closeout.
argument-hint: "[desired state]"
---

# Iterate

Advance the iteration from `<jj-root>/.agent/iterate.md`. The state file is the only iteration
interface; never use chat, summaries, commits, or other files as control state.

## Arguments

```
$ARGUMENTS
```

- Empty: resume the conventional state file.
- Non-empty: desired outcome for a new iteration.
- Never treat arguments as state-file paths.

## Rules

- Run planning before activation, review, and direct finalization as human-boundary procedures that
  stop after updating and rereading the state file. When review has displayed the current
  finalization candidate, normal review approval covers accepting the work and applying that
  displayed candidate; review may then continue to finalization in the same invocation.
- After explicit activation approval, run the active loop in the same invocation:
  `implement -> verify -> implement -> verify` until a stop condition is reached.
- Stop the active loop at review, blocked state, scope or boundary changes, required user decisions,
  unsafe or out-of-bound failures, context pressure that makes a fresh invocation safer, or any
  unapproved finalization/VCS lifecycle boundary.
- Keep implementation, verification, review, and finalization as distinct procedures. Compaction or
  fresh sessions are execution details and must not change the state model or stop conditions.
- Respect host and user approval gates. Host approval applies before state-file edits; activation
  approval is defined in `references/state-file.md`.
- Mutations, including revision lifecycle actions, are allowed only when the approved plan,
  boundaries, current procedure, or explicit approval of a displayed finalization candidate
  authorizes them.

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
Next: planning | implement | verify | review | finalize | none
```

Allowed control-field pairs:

- `Status: planning`, `Next: planning`
- `Status: active`, `Next: implement`
- `Status: active`, `Next: verify`
- `Status: review`, `Next: review`
- `Status: complete`, `Next: finalize`
- `Status: blocked`, `Next: none`
- `Status: finalized`, `Next: none`

## Runbook

1. Resolve workspace with `jj root`; stop if it fails.
2. Resolve state file as `<jj-root>/.agent/iterate.md`.
3. Missing state file: follow `procedures/new-iteration.md`.
4. Existing state file: read fresh; validate required sections and `Status` / `Next` using State
   Basics. Read `references/state-file.md` only when creating or repairing state-file structure,
   applying AC Stability, or checking task traceability.
5. Before following a procedure, read only the files it names for the current step; treat them as
   imported instructions, and do not preload files needed only by later procedures.
6. Before routing a non-terminal existing state, disambiguate intent: if the user clearly asks to
   abandon, replace, or do unrelated work, require explicit approval, then follow
   `procedures/new-iteration.md`; if intent is unclear, ask whether to resume, revise, or replace;
   otherwise route normally by status.
7. Combine the current user intent with the state machine's `Status` / `Next`, then validate the
   control fields form one allowed pair.
8. `Status: finalized` with a clear new desired outcome: follow `procedures/new-iteration.md`.
9. `Status: finalized` without a clear new desired outcome: ask what new iteration to draft and
   stop.
10. `Next: none`: report the current state and stop.
11. `Next: planning`: follow `procedures/planning.md`.
12. `Next: implement`: follow `procedures/implement.md`.
13. `Next: verify`: follow `procedures/verify.md`.
14. `Next: review`: follow `procedures/review.md`.
15. `Next: finalize`: follow `procedures/finalize.md`.
16. After planning activates the state or after an active procedure updates the state file, reread
    the state file. If the updated pair is `Status: active` with `Next: implement` or
    `Next: verify`, continue the active loop unless a stop condition was reached.
17. After review updates the state file, reread it. If review received approval after displaying the
    current finalization candidate and the updated pair is `Status: complete` with `Next: finalize`,
    immediately follow `procedures/finalize.md`. Otherwise stop.
18. After finalization, blocked state, `Next: none`, or any stop condition, reread the state file
    and stop.
19. When stopped, respond with:
    - State file path.
    - Final `Status` and `Next`.
    - Stop reason.
    - AC completion summary and open issues.
