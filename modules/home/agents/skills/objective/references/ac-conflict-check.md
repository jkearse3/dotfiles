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
2. Treat weakening as a conflict, not a harmless refinement. A candidate weakens an AC when it drops
   an invariant, narrows an output boundary, removes a failure mode, relaxes ownership, or makes old
   evidence appear to validate behavior it no longer covers.
3. Before any AC is considered stable, explicitly resolve every contradiction, supersession, or
   weakening. Update stale evidence notes when the AC remains valid; invalidate the AC when the old
   evidence or wording no longer supports the desired contract.
4. For unlocked ACs (`[ ]` and no task references `(ACN, ...)`), update the AC in place.
5. For locked ACs (marker is not `[ ]`, or task references exist), invalidate using the `[-]` +
   strikethrough + cross-reference format from `references/ac-stability.md` § AC Stability.
6. Present the conflict analysis to the user: which ACs will be updated, which invalidated, which
   evidence notes are stale or need replacement, and which new ACs will be added. If no conflicts
   exist, present the drafted ACs or candidates for approval.
7. Require user approval before any write to `## Acceptance Criteria`.
8. After approval, write all ACs to `## Acceptance Criteria`: existing ACs plus any
   updates/invalidations and new ACs numbered sequentially after the highest existing AC number.
