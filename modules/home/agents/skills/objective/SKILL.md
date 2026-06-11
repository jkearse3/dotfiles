---
name: objective
description: Objective workflow — spec, iterate, finalize reliable work with optional research/review helpers
argument-hint: "<intent or subcommand> [args]"
---

# Objective

Unified skill for the objective workflow. The primary lifecycle is `spec -> iterate -> finalize`:
define the contract, execute verified phases, then close out with PR-ready summary artifacts.

## Arguments

```
$ARGUMENTS
```

## Routing

Read the intent from the user-provided arguments and match it to an entry below, then read and
follow the matched procedure file. If the intent is ambiguous, ask the user to clarify. If no
arguments were provided, treat the request as `load`.

Procedure paths below are relative to `procedures/`.

Primary lifecycle:

- `spec [topic]` — `spec.md`: Define acceptance criteria and approach
- `iterate` (or `run all`) — `iterate.md`: Autonomous: pre-flight, loop all phases, auto-commit
- `finalize` — `finalize.md`: Close out the objective with PR-ready summary artifacts

Setup and navigation:

- `create [name]` — `create.md`: Create a new objective and branch
- `load` (or empty args) — `load.md`: Load the objective matching the current jj bookmark
- `switch [name]` — `switch.md`: Select an objective explicitly and move to its existing bookmark
- `list` — `list.md`: List all objectives
- `reset` — `reset.md`: Reset current objective to blank template
- `rename [name]` — `rename.md`: Rename objective, bookmark, and destination

Optional focused helpers:

- `research [topic]` or `investigate [topic]` — `investigate.md`: Invoke `/investigate` and merge
  findings into objective
- `interrogate [topic]` — `interrogate.md`: Invoke `/interrogate` and merge decisions into objective
- `phase-interrogate [topic]` — `phase-interrogate.md`: Apply interrogate workflow at the phase
  level
- `phase-scope` (or `scope phase`) — `phase-scope.md`: Scope next phase (dispatches scoping
  subagent)
- `phase-iterate [--auto-commit]` (or `iterate phase`) — `phase-iterate.md`: Run implement-verify
  loop inline for one phase
- Focused phase work requests — `phase-iterate.md`: If the user asks to implement, continue, fix,
  tweak, complete, or otherwise work on a focused or phase-scoped slice, route through
  `phase-iterate.md`; do not edit repo files inline in the main agent
- `review` — `review.md`: Autonomous review of branch changes, create cleanup phases
- `import-pr` (or `import pr comments`) — `import-pr.md`: Fetch unresolved PR comments as review
  phase

## Guardrail

In objective mode, never edit repo files without an active objective with approved ACs; all repo
edits go through `/objective iterate` or the focused helper `/objective phase-iterate`.

Focused or phase-scoped implementation/continue/fix/tweak/complete/work requests must route through
`procedures/phase-iterate.md`. The main agent must not satisfy those requests by editing repo files
inline.

## Cross-procedure references

When a procedure needs behavior from another, read that procedure file at `procedures/<name>.md` and
follow it inline — do not invoke the objective skill via the Skill tool to call it recursively.

## File conventions

Procedure, brief, and reference files may include `## References`. Before executing such a file,
read every listed reference. Treat references as imported instructions: formats, shared contracts,
and reusable operations in referenced sections govern the procedure steps.
