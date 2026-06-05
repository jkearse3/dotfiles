# Review

Orchestrate the autonomous branch-review pipeline: load the current objective, dispatch the pipeline
as a subagent, and present the returned summary.

Can be run at any point — not tied to phase completion. Useful for self-review after committing a
phase, general cleanup passes, or pre-PR review.

## References

- `references/contracts.md` — § Load Current Objective for the load/nudge gate.
- `references/branch-review.md` — § Autonomous Branch Review Conventions for the report fields
  returned by the subagent and presented by this orchestrator.

## Steps

1. Load state. Read `.objectives/_current/00-main.md` per `references/contracts.md` § Load Current
   Objective, including its no-objective nudge.

2. Dispatch the pipeline. Dispatch a subagent with prompt:

   ```text
   Read the bundled skill resource `briefs/branch-review.md` and execute the instructions within it.

   Context: This is an autonomous branch-level review (not a per-phase inner-loop review). Per-phase
   inner-loop verify is handled inline by `phase-iterate`.
   ```

3. Present the summary. After the subagent returns, present its summary per
   `references/branch-review.md` § Autonomous Branch Review Conventions.

## Contracts

### Invariants

- The orchestrator owns only the load/nudge gate, dispatch, and the user-facing summary; the
  subagent executes the pipeline.
- Preserve verbatim: the dispatch prompt and the report fields in `references/branch-review.md` §
  Autonomous Branch Review Conventions.
