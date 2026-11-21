---
name: iterate
description: >-
  Implements a requested change in a jj repository with implement, then reviews
  and fixes what it built with diff-fix until a review confirms no finding left
  to fix. Use when the user asks to iterate on a change, or to implement and
  review it in one go. For building alone use implement; for reviewing and
  fixing finalized revisions alone use diff-fix.
---

# Iterate

Follow `implement`, then `diff-fix` on what it built. Every rule and
authorization comes from those two skills; this skill adds only the hand-off.

## Implement

Follow `implement` with the request, and ask it to record `Then: iterate` in its
`run.md` header so the review still follows after compaction.

## Review

When `implement` ends `done` and created or changed a revision, follow
`diff-fix` on the revisions from the earliest one the run created or changed
through the tip, with:

- the criteria: the run's criteria and binding requirements, and its agreed spec
  from `run.md` `Spec`, whose acceptance criteria are the complete list of what
  the target may make visible, or the visible changes `Spec` records as that
  list in their place;
- the context: its exclusions;
- the user decisions: its settled decisions, its `Decisions` not prefixed
  `diff-fix:`, and this one: fixes, conflict resolutions, and reshapes change
  only revisions `implement` could change; a finding or conflict in any other
  revision needs the user;
- the decisions `diff-fix` took earlier: its `Decisions` prefixed `diff-fix:`.

Otherwise skip the review. During the review, record in `run.md` `Decisions`
each answer the user gives and, prefixed `diff-fix:`, each decision `diff-fix`
takes, as `diff-fix` records it.

## Report

Append `diff-fix`'s outcome to `run.md` `Outcome`. Report `implement`'s result,
then `diff-fix`'s, or why the review did not run.
