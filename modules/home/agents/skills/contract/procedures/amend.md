# Amend

Use this path when the user clearly asks to change an existing agreement, or
reconciliation shows the agreement is wrong, incomplete, stale, or ordered
incorrectly.

Read these references before acting:

- `references/local-state.md`
- `references/schema.md`
- `references/readiness.md`

Amendment changes agreement data. Reconciliation changes only AC markers and
evidence. Keep that distinction explicit.

Amendment may change conditional sections, spec, boundaries, milestone order,
outcomes, AC wording or checks, or add and remove milestones and ACs. Every
amendment requires explicit user approval before writing.

## Identity And Boundary Rules

- Preserve unaffected milestone IDs and AC numbers.
- Assign added milestones and ACs numbers above the highest retained number. Do
  not renumber retained entries merely to close gaps.
- Reset a changed AC to `[ ]` with `Evidence: Pending.`. Remove an obsolete AC
  instead of retaining a supersession chain; the contract represents the current
  agreement, not amendment history.
- Reset all AC evidence whose meaning, check, milestone outcome, order, or
  applicable boundary makes the prior result unreliable.
- Reordering, splitting, or merging milestones is a material agreement change.
  Ensure the resulting document order is a coherent acceptance sequence.
- Restoring regressed behavior may reuse its existing AC when the agreement and
  check are unchanged.

Before approval, inspect enough source to ground changed agreement claims and
run Contract Readiness against the complete amended agreement. If blocked,
report the finite approval-readiness state and blocker and stop. Only
`ready for approval` permits presenting the full amendment for explicit
approval.

After approval, run the Local State setup and verification required before a
contract update, then write only the contract file and minimum local
`.gitignore` state. Do not edit implementation files, other workflow state,
skill source, commits, revision descriptions, bookmarks, or branches while
amending. Never silently alter agreement data during reconciliation.
