# Planning

Use only for `Status: planning` with `Next: planning`.

Before activating a persisted plan, read:

- `references/bookmark-placement.md`
- `references/readiness.md`

Before showing a persisted plan for approval, or revising state-file structure,
ACs, or issues, read:

- `references/state-file.md`

Use Planning Draft Review and Persisted Plan Approval from
`references/state-file.md`. Do not run implement until the user explicitly
approves the exact persisted plan.

Planning must exhaust upfront alignment before approval. Pressure-test the plan
from multiple angles until both the agent and user agree there are no
approval-relevant holes. Ask sequential questions when answers shape later
questions; batch only independent questions. Never combine unresolved planning
questions with an activation approval request.

- No explicit plan approval yet: run Readiness. If material uncertainty remains,
  keep `Status: planning`, `Next: planning`, record concrete questions or
  approval-relevant gaps, follow Planning Draft Review, and stop. Otherwise
  confirm the plan has no unresolved approval-relevant questions or concerns,
  follow Persisted Plan Approval, then stop.
- Explicit approval of the exact persisted file most recently shown in chat: run
  Bookmark Placement and Readiness. If material uncertainty remains, keep
  `Status: planning`, `Next: planning`, record concrete questions, follow
  Planning Draft Review, and stop. Otherwise update only control fields to
  `Status: active`, `Next: implement`, reread the state file, and return to the
  active loop.
- User revisions are clear and in bounds: update the same file, run Readiness.
  If material uncertainty remains, keep `Status: planning`, `Next: planning`,
  record concrete questions or approval-relevant gaps, follow Planning Draft
  Review, and stop. Otherwise confirm the revisions resolve all currently known
  approval-relevant questions and concerns, follow Persisted Plan Approval, and
  stop.
- User revisions are unclear, contradictory, scope-expanding, or out of bounds:
  keep `Status: planning`, `Next: planning` with concrete questions when a safe
  draft remains possible; otherwise Block.
