# Finalize

Close out an objective after implementation by generating the PR-ready Summary
section.

## References

- `references/current-objective.md` — § Load Current Objective for the
  load/nudge gate.
- `references/workflow-invariants.md` — § Invariants for caller-token
  preservation and approval gates.

## Steps

1. Load the current objective per `references/current-objective.md` § Load
   Current Objective, including its no-objective nudge.

2. Review behavior. Do not run branch review from finalization. Final review
   remains on-demand via `/objective review`; review-created follow-up work must
   be handled with `/objective iterate` before running `/objective finalize`
   again.

3. Summary behavior. Read and follow `procedures/summarize.md` inline.

4. Report: `Objective finalized.`

## Contracts

- Final review is on-demand, not automatic. Use `/objective review` when final
  branch review is wanted.
- Review-created follow-up work remains owned by `/objective review`; execute
  that work before finalizing.
- Summary generation remains the required finalization artifact.
- Preserve verbatim: the `Objective finalized.` report string.
