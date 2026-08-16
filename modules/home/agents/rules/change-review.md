# Change Review

## Verify Revisions

Before finalizing each task revision, inspect its full diff, confirm its
description matches, and run focused checks proportionate to its claims and
risks.

A delegated implementer performs this verification for its revisions, but the
context owning the complete task remains responsible for aggregate review. If
the user declines finalization, report the task as unreviewed.

For a revision-local fix, create a fresh empty child directly on the revision
being fixed. Implement, inspect, and run focused verification on the isolated
fix, then squash it into the target revision. Do not implement the fix at the
stack tip. If the fix depends on later revisions, assign it to the appropriate
later revision or split it along revision boundaries. Do not edit the target
directly unless the fix cannot be represented safely through the
child-and-squash workflow.

After jj rebases descendants, inspect them for conflicts or unintended patch
changes and rerun only checks affected by the fix. A descendant whose patch and
meaning remain unchanged does not require repeated verification solely because
its commit ID or parent changed.

## Review The Task

After all task revisions are finalized, assign one independent reviewer to
review the aggregate task change. Review the assembled behavior, every
substantive task hunk, applicable criteria, and each task revision's diff and
description.

Determine scope from substantive work performed for the task. Unrelated
ancestors and mechanically rebased descendants are not part of the review merely
because they appear in the same branch stack. Include a descendant when the task
changes its patch, description, boundary, or meaning.

If independent review is unavailable, review the aggregate task change in the
owning context and report that the review was not independent.

Confirm each finding against source before accepting or rejecting it. Assign
each accepted finding to the mutable revision whose claim it changes and resolve
it through the revision-local fix workflow.

## After Review

Reverify later changes whose patch, meaning, or affected checks changed, and
refinalize any revision whose patch or meaning changed. Use judgment to scope
additional review to the change and its reachable effects. Repeat the aggregate
review only when the change materially affects the task as a whole or its impact
cannot be bounded confidently.

Completion requires verified task revisions, an aggregate task review, any
necessary follow-up review, satisfied criteria, and no accepted findings
remaining.
