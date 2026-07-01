# Review Handling

Human review follows agent verification and is outside AC completion. Agent success means
`Status: review`, `Next: review`: verified, awaiting human acceptance or follow-up.

Before handling in-bound feedback, read:

- `references/state-file.md`

- No user acceptance, closure, or change request yet: reread `.agent/iterate.md`; summarize AC
  evidence, issues, and the current `## Finalization Candidate`; then ask for review approval. State
  that approval accepts the work and applies the displayed closeout candidate. Stop after asking.
- User accepts or closes after review displayed the current finalization candidate: treat the
  approval as accepting the work and applying that displayed candidate. Set `Status: complete`,
  `Next: finalize`; reread `.agent/iterate.md`; then immediately follow `procedures/finalize.md`
  without a second approval round.
- Approval is unclear, or the current finalization candidate was not displayed before approval: set
  `Status: complete`, `Next: finalize`; reread `.agent/iterate.md`; stop before finalization and ask
  for explicit approval of the displayed current finalization candidate.
- User requests clear in-bound changes: treat as same-iteration feedback; update ACs/issues under AC
  Stability only as needed, set `Status: active`, set `Next: implement`, and stop. Do not edit repo
  files inline for the feedback.
- Feedback is unclear, contradicts ACs, expands scope, or violates boundaries: Block.
