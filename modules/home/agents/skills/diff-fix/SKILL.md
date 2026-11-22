---
name: diff-fix
description: >-
  Repeatedly reviews a finalized local jj revision, range, stack, or bookmark
  with diff-review, fixes the findings through fresh subagents, and loops until
  a review confirms no finding left to fix. Use when the user asks to fix,
  converge, or review-and-fix a finalized diff target in a jj repository. Not
  for working changes, Git-only checkouts, one-off bug fixes, read-only review,
  remote-only targets, or publication.
---

# Diff Fix

Review a finalized jj target, fix what the review confirms, and review again
until a review confirms nothing left to fix. This session coordinates: it runs
the loop, dispatches one fixer per round, checks each fix's diff, and decides
what the user's decisions leave open. It never reviews the target or edits code;
if the host cannot start fresh agents, stop and report.

Rounds share only the user's decisions, the decisions this session takes, every
review's confirmed findings, and the last review's declined candidates. This
session passes findings on without matching them; each review judges which still
hold or keep recurring and finds again whatever else is still wrong. Never lower
the finding bar, edit criteria, or phrase requests to suppress findings.

## Target

Resolve the target as `diff-review` does, and require a jj repository, no
`<target> & immutable()` revisions, and an empty `@` above the target. Before
each review and at the end, `@` is an empty child of the target's tip. Refer to
revisions by change ID, since every squash rewrites commits.

Take criteria, context, user decisions, decisions this session took earlier, and
check evidence from the request. Invoking this skill authorizes squashing fixes
into any target revision and rebasing its descendants within the task's stack; a
reshape needs a user decision, and no other revision changes.

## Decisions

This session decides, instead of asking the user, each `design` or `question`
finding no decision settles, each fixer's `needs-decision` return, and whether
to accept each fixer's `rejected` return. It takes the option the evidence best
supports that stays within the criteria and decisions; when no option does, it
sets the finding aside for the Report. It records each decision with the
finding, the option taken, the options rejected, the evidence, the revisions its
fix touched, and its kind: `taste` when the evidence favors no option and the
choice is preference, such as naming, wording, or which of two sound designs to
keep, and `evidence` otherwise.

## Loop

1. **Review.** Resolve the target from its base to its current tip and follow
   `diff-review` on the whole target in this session, with the request's
   granularity, as a session that must stay independent of it: this session
   dispatches its reviewer and verifier and never hands the whole review to one
   subagent, which could not dispatch them. Give the review the criteria, the
   context, the check evidence, every user decision and every decision this
   session took so far, every earlier review's confirmed findings as its earlier
   findings, the last review's declined candidates with their evidence, and a
   request to run the repository's checks at the tip. `blocked` stops the run.
2. **Finish** when no confirmed finding is left to fix. First set aside for the
   Report every confirmed finding this run lacks authority to fix: one owned
   outside the target, one whose owner has a descendant outside the task's stack
   that the user has not authorized rebasing, and one whose fix needs
   reordering, splitting, or moving changes between revisions. Then decide each
   `design` or `question` finding no decision settles. Criteria `not satisfied`,
   areas a review leaves uncovered, and criteria it cannot decide, `blocked` or
   checkable only by a person, never block finishing and go to the Report.
   Otherwise, after every fifth review, or as often as the request sets, ask the
   user whether to continue before fixing, giving each review's number of
   confirmed findings.
3. **Fix** the findings left to fix through one fresh fixer for the whole
   target. Record the current operation ID
   (`jj op log -n1 --no-graph -T 'id.short()'`) and the commit ID of each
   revision in `descendants(<target's first revision>)` and of that revision's
   parents, then dispatch the fixer with the target's change IDs, those findings
   with their owners, the criteria and context, and every decision. The fixer
   follows `coding-style`, performs no delegation, and fixes each finding's root
   cause on every path its owner holds; the next review raises paths that later
   revisions hold. It visits owners earliest first: `jj new <owner>`, edit, then
   `jj squash --into <owner>`. When a squash leaves a target revision
   conflicted, it resolves the conflict the same way in that revision, keeping
   the revision's intent. When a fix makes its owner's description inaccurate or
   a finding concerns the description, it composes a replacement from the
   description, the facts, and the fix's diff as `finalize-changes`' Runbook
   step 3 does, formats it with `commit-message format`, validates that exact
   value with `commit-message validate --require-body` and the options
   `references/revision-descriptions.md` sets, and sets it with
   `jj describe <owner> --message "$desc"`. It runs no other VCS mutation, such
   as a reorder, split, or push, touches no revision outside the target, and
   ends with `jj new <tip>`. Before returning, it reviews its fixes for defects
   they add as the Trace section of `diff-review`'s `references/reviewer.md`
   does, judged by `references/findings.md`, and fixes what it finds. Per
   finding it returns `fixed` with the revision it changed and each check it ran
   and the result, only once those checks pass at the owner, `rejected` with
   evidence, or `needs-decision` with the question, and it names any conflict it
   could not resolve. Decide each `needs-decision` and `rejected` return for
   later rounds.

4. **Check** what the fixer changed against the recorded commits. No revision
   but `@` may have joined or left `descendants(<target's first revision>)`,
   that revision's parents must keep their commits, `@` must be an empty child
   of the tip, and
   `jj log -r 'descendants(<target's first revision>) & conflicts()'` must list
   nothing. For each target revision whose commit changed,
   `jj interdiff --from <recorded commit> --to <change ID>` must hold only the
   fixes and conflict resolutions the fixer reported, and for each other changed
   revision except `@` it must be empty. Every check the fixer reports for a
   `fixed` finding must have a passing result, and every changed description
   must pass the validation step 3 names. When any of this fails, stop the run
   as `stopped` and report this round's operations, those after the recorded one
   that `jj op log` lists with this run's commands, which
   `jj op revert <operation>` undoes newest first; never offer `jj op restore`,
   which also undoes other workspaces' operations. A `fixed` finding whose diff
   does not fix it has not landed; the next review raises it.
5. Return to step 1.

## Report

Open with **Decisions to review**: every `taste` decision, then every `evidence`
decision, each as Decisions records it, and offer to apply a different option to
any of them. Then give the outcome, `finished`, `blocked`, `stopped` with its
reason, or `stopped by user`, and the number of reviews, and list the last
review's open findings, the findings set aside with why, each criterion still
`not satisfied` that the user has not accepted, the areas the review left
uncovered and the criteria it could not decide, revisions rewritten and
descendants rebased, and where `@` ends. Offer to act on any open or set-aside
finding or unsatisfied criterion.
