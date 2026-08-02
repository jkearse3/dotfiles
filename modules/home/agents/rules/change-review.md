# Change Review

## Verify Revisions

Before finalizing each task revision, inspect its full diff, confirm its
description matches, and run focused checks proportionate to its claims and
risks.

A delegated implementer performs this verification for its revisions, but the
context owning the complete task remains responsible for aggregate review. If
the user declines finalization, report the task as unreviewed.

Fix a defect in the mutable revision whose claim it changes. Rerun verification
when a rewrite changes a revision's patch or meaning. A mechanically rebased
descendant does not require repeated verification solely because its commit ID
or parent changed.

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

Confirm each finding against source before accepting or rejecting it. Fix
accepted findings in the revision whose claim they change while that history
remains mutable.

## After Review

Reverify and refinalize every later change. Use judgment to scope any additional
review to the change and its reachable effects. Repeat the aggregate review only
when the change materially affects the task as a whole or its impact cannot be
bounded confidently.

Completion requires verified task revisions, an aggregate task review, any
necessary follow-up review, satisfied criteria, and no accepted findings
remaining.
