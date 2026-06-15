# Planning

Use only for `Status: planning` with `Next: none`.

Before activating a persisted plan, read:

- `references/bookmark-placement.md`
- `references/readiness.md`

Before showing a persisted plan for approval, or revising state-file structure, ACs, or issues,
read:

- `references/state-file.md`

Use Persisted Plan Approval from `references/state-file.md`. Do not dispatch implement until the
user explicitly approves the exact persisted plan.

- No explicit plan approval yet: follow Persisted Plan Approval, then stop.
- Explicit approval of the exact persisted file most recently shown in chat: run Bookmark Placement
  and Readiness. If material uncertainty remains, keep `Status: planning`, `Next: none`, record
  concrete questions, follow Persisted Plan Approval, and stop. Otherwise update only control fields
  to `Status: active`, `Next: implement`, and return to normal runbook routing.
- User revisions are clear and in bounds: update the same file, follow Persisted Plan Approval, and
  stop.
- User revisions are unclear, contradictory, scope-expanding, or out of bounds: keep
  `Status: planning`, `Next: none` with concrete questions when a safe draft remains possible;
  otherwise Block.
