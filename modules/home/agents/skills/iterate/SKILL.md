---
name: iterate
description: >-
  Implements a requested change in a jj repository with implement, then reviews
  and fixes what it built with diff-fix until a review confirms no findings. Use
  when the user asks to iterate on a change, or to implement and review it in
  one go. For building alone use implement; for reviewing and fixing finalized
  revisions alone use diff-fix.
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

- the criteria: the run's criteria and binding requirements;
- the context: its exclusions;
- the user decisions: its settled decisions, its `Decisions`, and this one:
  fixes, conflict resolutions, and reshapes change only revisions the user
  authored, pushed or not, the request names, or the run created; a finding or
  conflict in any other revision needs the user.

Otherwise skip the review. During the review, record each answer the user gives
in `run.md` `Decisions`.

## Report

Append `diff-fix`'s outcome to `run.md` `Outcome`. Report `implement`'s result,
then `diff-fix`'s, or why the review did not run.
