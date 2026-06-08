---
name: objective
description: Objective workflow — create, load, investigate, spec, scope, iterate, review, summarize
argument-hint: "<intent or subcommand> [args]"
---

# Objective

Unified skill for the objective workflow. Routes the user-provided arguments to the matching
procedure file.

## Arguments

```
$ARGUMENTS
```

## Routing

Read the intent from the user-provided arguments and match it to an entry below, then read and
follow the matched procedure file. If the intent is ambiguous, ask the user to clarify. If no
arguments were provided, treat the request as `load`.

Procedure paths below are relative to `procedures/`.

- `create [name]` — `create.md`: Create a new objective and branch
- `load [name]` (or empty args) — `load.md`: Load an existing objective (branch-aware)
- `list` — `list.md`: List all objectives
- `reset` — `reset.md`: Reset current objective to blank template
- `rename [name]` — `rename.md`: Rename objective, bookmark, and destination
- `interrogate [topic]` — `interrogate.md`: Invoke `/interrogate` and merge decisions into objective
- `phase-interrogate [topic]` — `phase-interrogate.md`: Apply interrogate workflow at the phase
  level
- `investigate [topic]` — `investigate.md`: Invoke `/investigate` and merge findings into objective
- `spec [topic]` — `spec.md`: Define acceptance criteria and approach
- `phase-scope` (or `scope phase`) — `phase-scope.md`: Scope next phase (dispatches scoping
  subagent)
- `phase-iterate [--auto-commit]` (or `iterate phase`) — `phase-iterate.md`: Run implement-verify
  loop inline for one phase
- `iterate` (or `run all`) — `iterate.md`: Autonomous: pre-flight, loop all phases, auto-commit
- `review` — `review.md`: Autonomous review of branch changes, create cleanup phases
- `import-pr` (or `import pr comments`) — `import-pr.md`: Fetch unresolved PR comments as review
  phase
- `summarize [--auto]` — `summarize.md`: Generate PR description from objective

## Guardrail

In objective mode, never edit repo files without an active objective with approved ACs; all repo
edits go through `/objective phase-iterate` or `/objective iterate`.

## Cross-procedure references

When a procedure needs behavior from another, read that procedure file at `procedures/<name>.md` and
follow it inline — do not invoke the objective skill via the Skill tool to call it recursively.

## File conventions

Procedure, brief, and reference files may include `## References`. Before executing such a file,
read every listed reference. Treat references as imported instructions: formats, shared contracts,
and reusable operations in referenced sections govern the procedure steps.
