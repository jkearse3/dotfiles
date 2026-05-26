# Review

Orchestrate the autonomous branch-review pipeline: load the current objective, dispatch the pipeline
as a subagent, and present the returned summary.

Can be run at any point — not tied to phase completion. Useful for self-review after committing a
phase, general cleanup passes, or pre-PR review.

## References

- `references/contracts.md` — § Load Current Objective for the load/nudge gate.

## Steps

1. Load state. Read `.objectives/_current/00-main.md` per `references/contracts.md` § Load Current
   Objective. If no objective: nudge — "No active objective. Want me to load or create one?"

2. Dispatch the pipeline. Dispatch a subagent with prompt:

   ```text
   Read the file at ~/.claude/skills/objective/briefs/branch-review.md and execute the instructions within it.

   Context: This is an autonomous branch-level review (not a per-phase inner-loop review). Per-phase
   inner-loop verify is handled inline by `phase-iterate`.
   ```

3. Present the summary. After the subagent returns, present its summary (see § Report).

## Contracts

### Report

The subagent returns, and the orchestrator presents, this summary:

- Phases created (count and names).
- Concern counts by source (human REVIEW comments vs. code review findings).
- Out-of-scope concerns flagged (count, if any).
- Suggest: `/objective phase-iterate` to execute.

### Invariants

- The orchestrator owns only the load/nudge gate, dispatch, and the user-facing summary; the
  subagent executes the pipeline.
- Preserve verbatim: the dispatch prompt, the no-objective nudge, and the Report fields.
