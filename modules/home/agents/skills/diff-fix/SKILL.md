---
name: diff-fix
description: >-
  Repeatedly reviews a finalized local jj revision, range, stack, or bookmark
  with diff-review, fixes the findings through fresh subagents, and loops until
  a review confirms no findings. Use when the user asks to fix, converge, or
  review-and-fix a finalized diff target in a jj repository. Not for working
  changes, Git-only checkouts, one-off bug fixes, read-only review, remote-only
  targets, or publication.
---

# Diff Fix

Review a finalized jj target, fix what the review confirms, and review again
until a review confirms nothing. This session coordinates: it runs the loop,
reads each fix's diff to land it, writes replacement descriptions, and asks the
user. It never reads the target's hunks, reviews, or edits code; if the host
cannot start fresh agents, stop and report.

Rounds share only the user's decisions, every review's confirmed findings, and
the last review's declined candidates. This session passes findings on without
matching them; each review judges which still hold or keep recurring and finds
again whatever else is still wrong.

## Target

Resolve the target as `diff-review` does, and require a jj repository, no
`<target> & immutable()` revisions, and an empty `@` above the target. Before
each review and at the end, `@` is an empty child of the target's tip. Refer to
revisions by change ID, since every squash rewrites commits.

Take criteria, context, user decisions, and check evidence from the request.
Invoking this skill authorizes squashing fixes into target revisions and
rebasing their descendants, and a user decision to reshape the target authorizes
that reshape. It authorizes nothing outside the target and no publication.

## Loop

1. **Review.** Resolve the target from its base to its current tip and follow
   `diff-review` on the whole target in this session, with the request's
   granularity, as a session that must stay independent of it: this session
   dispatches its reviewer and verifier and never hands the whole review to one
   subagent, which could not dispatch them. Give the review the criteria, the
   context, the check evidence, any request in the user's own words for two
   independent reviewers, every user decision so far, every earlier review's
   confirmed findings as its earlier findings, the last review's declined
   candidates with their evidence, and a request to run the repository's checks
   at the tip. `blocked` stops the run.

2. **Finish** when the review confirms no findings and no criterion
   `not satisfied` that the user has not accepted. Areas a review leaves
   uncovered and criteria it cannot decide, `blocked` or checkable only by a
   person, never block finishing and go to the Report, not to the user.
   Otherwise, after every fifth review, ask the user whether to continue before
   fixing, giving each review's number of confirmed findings.
3. **Fix** only the findings the review confirmed. Set aside for step 6 every
   one that needs the user: one owned outside the target, one whose fix needs
   reordering, splitting, or moving changes between revisions, and a `design` or
   `question` finding no user decision settles. For the rest, visit each owning
   revision, earliest first. Run `jj new <owner>` and dispatch a fresh fixer
   with the owner's change ID, its findings, the criteria and context, and the
   user's decisions. The fixer follows `coding-style`, edits only the working
   copy, performs no VCS mutation or delegation, and fixes each finding's root
   cause on every path the owner holds; the next review raises paths that later
   revisions hold. It never writes description text; when a finding concerns the
   owner's description or the description no longer holds, it returns the facts.
   Per finding it returns `fixed` with each check it ran and the result,
   `rejected` with evidence, or `needs-decision` with the question. Land each
   owner before visiting the next.
4. **Land.** For description facts, compose the replacement from the owner's
   description, the facts, and the fix's diff as `finalize-changes`'
   `references/revision-descriptions.md` requires, never mentioning reviews or
   fixes. Confirm the fix's diff and any replacement fix each `fixed` finding,
   change nothing else, and pass the fixer's checks; then run
   `jj squash --from @ --into <owner>`, adding `--message "$desc"` for a
   replacement, or, when only the description changes,
   `jj describe <owner> --message "$desc"`. Otherwise run `jj abandon @`; the
   next review raises what is still wrong.
5. **Resolve conflicts** after each landing. List
   `jj log -r 'descendants(<owner>) & conflicts()' --reversed`. For the earliest
   conflicted target revision, run `jj new` on it and dispatch a fresh fixer
   under step 3's rules with the revision's description and the landed fix. Land
   the resolution into the conflicted revision as step 4 lands a fix, confirming
   it keeps the revision's intent and carries the landed fix, and list again.
   When a resolution fails, leave the revision conflicted, stop fixing for this
   round, and ask about it in step 6. Once no target revision is conflicted,
   stop the run if a revision outside the target has become conflicted.
6. **Ask** the user, at once, about the findings set aside in step 3, the
   fixers' `rejected` and `needs-decision` returns with their evidence,
   unresolved conflicts, and each criterion `not satisfied` that the user has
   not accepted and no fix landed for this round, offering decide or stop. For a
   decided reshape, a fresh agent follows `finalize-changes` with the target as
   its mutable history set and the decision as its boundary intent and returns
   its report; if it stops, stop the run and report its state.
7. Return to step 1.

## Report

Lead with the outcome, `finished`, `blocked`, or `stopped by user`, and the
number of reviews. Then list the last review's open findings, the areas it left
uncovered and the criteria it could not decide, revisions rewritten and
descendants rebased, and where `@` ends.

## Boundaries

- Never push, publish, or mutate external systems.
- Never rewrite references outside the target, except rebasing its descendants.
- Never lower the finding bar, edit criteria, or phrase requests to suppress
  findings.
