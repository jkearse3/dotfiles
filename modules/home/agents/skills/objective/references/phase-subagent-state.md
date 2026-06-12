# Phase Subagent State

State-loading contract shared by phase subagent briefs.

## Load Phase Subagent State

Read the phase state file provided by the orchestrator and load the sections the caller needs:

- `### Context` — phase intent and any delegated context.
- `### Approach` — strategy, constraints, and implementation patterns.
- `### Tasks` — work items and AC/task annotations.
- `### Issues` — existing issues for follow-up or deduplication.
- `### Verification Hints` — phase-specific negative checks, forbidden output, stale evidence, and
  search terms to use during later validation.
- `### Continuation` — read-only resume context from a routed follow-up, if present.

Use `### Continuation` only to understand why the subagent resumed. Do not create, update, clear, or
route continuation; lifecycle decisions remain with the orchestrating procedure.

Read `.objectives/_current/00-main.md` `## Acceptance Criteria` for AC text used by later
brief-specific assessment or validation steps.
