---
name: goal
description: Goal workflow — create, load, investigate, spec, scope, iterate, review, summarize
argument-hint: "<intent or subcommand> [args]"
---

# Goal

Unified skill for the goal workflow. Routes the user-provided arguments to the matching procedure
file.

## Arguments

```
$ARGUMENTS
```

## Routing

Read the intent from the user-provided arguments and match it to an entry below, then read and
follow the matched procedure file. If the intent is ambiguous, ask the user to clarify. If no
arguments were provided, treat the request as `load`.

Procedure paths below are relative to `procedures/`.

- `create [name]` — `create.md`: Create a new goal and branch
- `load [name]` (or empty args) — `load.md`: Load an existing goal (branch-aware)
- `list` — `list.md`: List all goals
- `reset` — `reset.md`: Reset current goal to blank template
- `rename [name]` — `rename.md`: Rename goal, bookmark, and destination
- `investigate [topic]` — `investigate.md`: Invoke `/investigate` and merge findings into goal
- `spec [topic]` — `spec.md`: Define acceptance criteria and approach
- `phase-scope` (or `scope phase`) — `phase-scope.md`: Scope next phase (dispatches scoping
  subagent)
- `phase-iterate [--auto-commit]` (or `iterate phase`) — `phase-iterate.md`: Run implement-verify
  loop inline for one phase
- `iterate` (or `run all`) — `iterate.md`: Autonomous: pre-flight, loop all phases, auto-commit
- `review` — `review.md`: Autonomous review of branch changes, create cleanup phases
- `import-pr` (or `import pr comments`) — `import-pr.md`: Fetch unresolved PR comments as review
  phase
- `summarize [--auto]` — `summarize.md`: Generate PR description from goal

## Guardrail

In goal mode, never edit repo files without an active goal with approved ACs; all repo edits go
through `/goal phase-iterate` or `/goal iterate`.

Research spikes are exempt: `/goal investigate` without an active goal is allowed and auto-creates
one when the spike reveals concrete work.

## Cross-procedure references

When a procedure needs behavior from another, read that procedure file at `procedures/<name>.md` and
follow it inline — do not invoke the goal skill via the Skill tool to call it recursively.
