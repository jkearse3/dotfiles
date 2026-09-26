---
name: diff-fix
description: >-
  Repeatedly reviews a finalized local jj revision, range, stack, or bookmark
  with diff-review, fixes the findings through fresh subagents, and loops until
  a full review passes. Use when the user asks to fix, converge, or
  review-and-fix a finalized diff target in a jj repository. Not for working
  changes, Git-only checkouts, one-off bug fixes, read-only review, remote-only
  targets, or publication.
---

# Diff Fix

Drive a finalized jj target to a literal `diff-review` `pass` by alternating
fresh reviewer and fresh fixer subagents. This session coordinates: it keeps the
findings list, verifies and lands fixes, and asks the user. It never reviews or
fixes itself; if the host cannot start fresh agents, stop and report.

## Target

Resolve the target as `diff-review` does, and require a jj repository, no
`<target> & immutable()` revisions, and an empty `@` above the target. Record
any bookmark name, and refer to the target and every owning revision by change
ID, never commit ID, because each squash rewrites commits.

Take the declared criteria, context, and any user decisions from the request.
Invoking this skill authorizes squashing fixes into target revisions and
rebasing their descendants. It authorizes nothing outside the target and no
publication.

## Findings

Keep a findings list in the conversation. Each finding has its mechanism, its
location from the latest review, its owning revision, a status (`open`, `fixed`,
`settled`, or `needs-decision`), and its latest attempt or ruling with the
evidence or reason. A finding stays `open` until its fix lands, a reviewer
declines it with a reason, it needs a decision, or the user decides it.

Every reviewer and fixer receives the criteria, context, and user decisions
verbatim, plus the findings list. Settled findings and user decisions are
earlier conclusions, re-raised only when the current code shows their reason no
longer holds.

Match findings across rounds by mechanism, not wording or line. A finding
against the change a landed fix made re-raises that fix's finding.

## Loop

1. **Review.** Dispatch a fresh reviewer to follow `diff-review` read-only: no
   edits, VCS mutation, scratch files in the repository, or delegation. Per
   finding it returns category, location, mechanism, and owning revision (the
   earliest target revision whose diff introduces the defect), and it confirms
   or declines with a reason each `open` finding it was given. Return an
   incomplete review to the reviewer. `pass` ends the run; `blocked` stops it.
2. **Triage.** A finding a user decision covers takes that decision's effect. A
   reasoned decline settles a finding unless the user asked for that change.
   `design` and `question` findings, findings owned outside the target,
   re-raised `needs-decision` findings, and re-raises that meet the first Ask
   trigger are `needs-decision`. Everything else is `open`.
3. **Ask** the user when a trigger below holds, before fixing. Present the
   `needs-decision` findings with their history and any unsatisfied criteria,
   and offer: decide, continue, or stop. A decision calling for a change makes
   the finding `open`; one to leave the code as is settles it. Triggers:
   - a reviewer re-raises a `fixed` or `settled` finding, or an `open` one whose
     latest attempt is an evidenced rejection, and no user decision covers it;
   - the review did not pass and nothing is `open`;
   - 5 reviews since the last user checkpoint have not passed, unless a user
     decision set another limit.
4. **Fix.** For each owning revision with `open` findings, earliest first, run
   `jj new <owner>` and dispatch a fresh fixer. It follows `coding-style`, edits
   only the working copy, performs no VCS mutation or delegation, and returns
   per finding `fixed` with checks run, `rejected` with concrete evidence, or
   `needs-decision` with the question. It also returns replacement text when the
   owner's description became inaccurate.
5. **Land.** Confirm the diff addresses each `fixed` finding, changes nothing
   else, and passes checks; otherwise abandon the working copy and keep those
   findings `open` as unverified. A rejection without evidence stays `open` as
   unverified; a rejection of a change the user asked for, or a `needs-decision`
   return, makes it `needs-decision` with the question. Validate any replacement
   description as `finalize-changes` describes, then run
   `jj squash --from @ --into <owner>`, adding `--message "$desc"` for a
   replacement. A description-only fix squashes the empty working copy with a
   message. Mark the landed findings `fixed`.
6. **Resolve conflicts** before the next fix. After each landing, list
   `jj log -r 'descendants(<owner>) & conflicts()' --reversed`. While a target
   revision is conflicted, run `jj new` on the earliest one and dispatch a fresh
   fixer under the step 4 rules with its change ID, its description, and the
   landed findings, to keep the revision's intent and carry the fix. Land its
   resolution the same way and list again. Stop and ask the user when a
   resolution fails verification or needs a decision. Then stop when a
   descendant outside the target is newly conflicted.
7. After all fixes, run `jj new <target tip>` before the next review.

## Report

Lead with the outcome: `pass`, `blocked`, or `stopped by user`, with the final
`diff-review` report. Then list rewritten revisions, rebased descendants outside
the target, where `@` ends, findings by status, and checks run and skipped.

## Boundaries

- Never push, publish, or mutate external systems.
- Never rewrite references outside the target, except rebasing its descendants.
- Never lower the pass bar, edit criteria, or phrase requests to suppress
  findings.
