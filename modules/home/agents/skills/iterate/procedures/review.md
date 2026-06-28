# Review Handling

Human review follows agent verification and is outside AC completion. Agent success means
`Status: review`, `Next: review`: verified, awaiting human acceptance or follow-up.

Before handling in-bound feedback, read:

- `references/state-file.md`

- No user acceptance, closure, or change request yet: summarize AC evidence and issues, then stop.
- User accepts or closes: set `Status: complete`, `Next: finalize`; then stop.
- User requests clear in-bound changes: treat as same-iteration feedback; update ACs/issues under AC
  Stability only as needed, set `Status: active`, set `Next: implement`, and stop. Do not edit repo
  files inline for the feedback.
- Feedback is unclear, contradicts ACs, expands scope, or violates boundaries: Block.
