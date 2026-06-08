# AC Conflict Check

Approval-gated conflict check for new objective acceptance criteria.

## AC Conflict Check

Use this operation before writing new objective ACs that were drafted from a topic-scoped spec
change or surfaced as objective AC candidates during phase interrogation.

Inputs:

- Existing `## Acceptance Criteria` from `00-main.md`.
- New AC candidates after caller-specific deduplication.
- Existing task references in any phase, used to determine whether an AC is locked.

Apply the lifecycle:

1. Scan each existing AC for contradiction, overlap, or supersession by a new candidate.
2. For unlocked ACs (`[ ]` and no task references `(ACN, ...)`), update the AC in place.
3. For locked ACs (marker is not `[ ]`, or task references exist), invalidate using the `[-]` +
   strikethrough + cross-reference format from `references/ac-stability.md` § AC Stability.
4. Present the conflict analysis to the user: which ACs will be updated, which invalidated, and
   which new ACs will be added. If no conflicts exist, present the drafted ACs or candidates for
   approval.
5. Require user approval before any write to `## Acceptance Criteria`.
6. After approval, write all ACs to `## Acceptance Criteria`: existing ACs plus any
   updates/invalidations and new ACs numbered sequentially after the highest existing AC number.
