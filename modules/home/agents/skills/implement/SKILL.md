---
name: implement
description: >-
  Implements an agreed change in a jj repository by planning, verifying, and
  landing one revision at a time, then reviews and fixes what it built with
  diff-fix unless the user defers review for a draft. Use when the user asks to
  implement, build, or carry out a change from a request, issue, plan, note, or
  spec, to draft or iterate on a change without review yet, or says a draft is
  ready for review. Not for fixing findings on other finalized work (use
  diff-fix), read-only investigation or review, Git-only checkouts, or
  publication.
---

# Implement

Turn a described change into finalized, independently valid revisions on the
user's current branch, then review and fix them with `diff-fix` unless the user
defers review. This session owns the work and the run record. Agree what will
change, then plan, build, verify, and land the next revision from the code
already landed. Delegate a bounded piece only when it helps.

## Input

Take the change from the request and context: the request itself, a file, an
issue, a note, a plan, a spec, or the conversation. Draw from it the outcome,
criteria, exclusions, settled decisions, and binding requirements such as
constraints and prescribed implementation details, keeping their wording. From a
spec in the shape `spec` defines, take `Goal` as the outcome, the acceptance
criteria as the criteria and the complete list of what may become visible,
`Boundaries` as the exclusions and binding constraints, and each `Why:` line as
a settled decision. A spec with a `Changes` section predates that shape; use it
as input to `spec` rather than building it as written. Settled decisions count
as user decisions.

## Review Mode

A run reviews what it builds unless review is deferred. Review is deferred when
the user asks to defer it, such as for a draft, a spike, or iterating on a
change before it is ready. It also stays deferred while the branch's bookmark
has a deferred run and the user does not ask for review. In the run's first
message to the user, say in one line whether the run will review or defer
review, and that they can switch it by saying so.

A bookmark's deferred runs are the runs in the run store, which
`agent-store dir --workspace <workspace-root> implement` prints, whose `run.md`
header names the bookmark and records `Review: deferred`, and at least one of
whose recorded revisions is still in `mutable() & ::<bookmark>`. A run whose
revisions all left that set, such as earlier work under a reused bookmark name
or a draft that was abandoned or landed, is ignored.

## Outcomes

Hold these throughout, choosing the jj commands; when one cannot hold, that
needs the user.

- **One branch.** The run works on the branch `@` sits on (`mutable() & ::@-`)
  plus the revisions it adds. It starts only from an empty, undescribed `@` on a
  linear branch of described revisions; otherwise stop and say why. When the
  request names a revision off that branch, ask the user to check out its
  branch.
- **Valid history.** Every revision the run creates or changes holds one
  concern, is described as `finalize-changes`'
  `references/revision-descriptions.md` requires, and is valid on its own under
  `finalize-changes`' Sequencing. A change lands in a new revision or in the
  existing revision whose concern it belongs to, and later revisions that use it
  are updated to match.
- **Nothing else moves.** No revision off the branch changes. On it, folds and
  conflict resolutions rewrite what the version-control rules allow in the
  task's stack, plus any revision the request names.
- **A bookmark marks the tip.** The task bookmark always points at the branch's
  tip.
- **A clean working copy.** Between changes and when asking the user, as at the
  end, `@` is an empty child of the tip with no unlanded attempt on the branch.
- **Resumable.** `run.md` holds enough to resume after compaction.

After checking that the run can start, run
`scripts/prepare-run.sh --workspace <workspace-root> <slug>` by its path, with
the workspace's absolute root and a short slug for the outcome. It prepares the
ignored `.agent/implement/` store and prints a new run directory's absolute
path. On failure, never fall back to the scratchpad or the workspace. Never
track, publish, or delete the store or a run directory. Invoking this skill
authorizes writing them and abandoning attempts that did not land.

## Run Record

Only this session writes `run.md` in the run directory, except where the Review
section has a later review write there. Record decisions and landed results, not
routine steps. On resume, reread it. Reconcile recorded revisions, the bookmark,
and the working copy with jj before continuing; do not absorb unaccounted-for
work. The record holds:

- a header: workspace path, branch base, bookmark, input source, and, when
  review is deferred, `Review: deferred`, which becomes `Review: done` once a
  review of the run's revisions ends `finished`;
- `Input`: the outcome, criteria, exclusions, settled decisions, and binding
  requirements verbatim, or, for an input file in the run store's `.agent/`
  directory, its path and which sections hold each;
- `Decisions`: each user answer, dated, including a handover and each choice
  made under it with the option it rejected, and each decision `diff-fix` takes,
  prefixed `diff-fix:`;
- `Spec`: the path of the agreed spec and the date the user agreed it or handed
  it over; otherwise, the visible changes the input settles, with evidence from
  `Input`, or an explanation that the work makes none;
- `Revisions`: one list of revisions the run landed or changed, with their
  change and commit IDs, criteria served, check commands and results, and
  unsettled suspected defects. If interrupted, record any unfinished attempt and
  where to find it separately from landed results;
- `Outcome`, written at the end, with `diff-fix`'s outcome appended when a
  review runs.

## Loop

1. **Confirm the outcome and order.** Read enough of the code to apply
   Alignment. If the input leaves a visible change unsettled, use `spec` and get
   agreement before building. Record the agreement in `Spec`; it bounds the
   work. Sketch the dependency order for the remaining work. Keep the order and
   boundaries of any agreed milestones instead of making a second roadmap.
2. **Plan, build, and verify the next revision.** Establish the authorized
   parent or fold target before editing, and put a fresh working copy where the
   change belongs. Plan only this revision in detail. The same agent plans,
   edits, runs the applicable checks, and reviews the complete diff. Follow
   `coding-style` and the Change Review rule. Do not pause between planning and
   editing unless a user-owned decision the handover, if any, does not cover
   remains, or the work would depart from the agreement in a way the Alignment
   rule does not let you amend. If that happens during editing, stop before
   landing, keep any unfinished work separate from the verified tip, and present
   the deviation and evidence.

   If delegating, give the agent the path to `run.md`, the authorized target,
   scope, and expected evidence. It edits only the task working copy and does
   not change the revision stack, move the working copy, or delegate further. It
   returns the checked commit, check commands and results, and any unsettled
   suspected defects, or explains what blocks the change. This session owns
   finalization.

3. **Land, record, and repeat.** Verify that the diff serves the agreed criteria
   and the checks cover the tree that lands. Follow `finalize-changes` to land
   it and apply its description rules. After a fold, inspect the affected
   descendants. Resolve conflicts in dependency order only within the authorized
   stack, preserving each revision's intent, and rerun affected checks,
   including at the tip. Do not continue with unresolved conflicts or known
   failures. Before advancing an agreed milestone, confirm its checks pass at
   its tip; reuse results on the same tree.

   Record the landed revision and its verification and update any affected
   entries after a fold. Confirm the task bookmark and empty working copy under
   Outcomes. Take the next revision from what is now landed. When no work
   remains, confirm the agreed criteria and follow the Change Review rule for
   the aggregate change before the review.

## Review

Review when the loop ends `done` having created or changed a revision and review
is not deferred, and, without building, when the user says a draft is ready or
asks to review it. The review covers the reviewed runs: this run, if any, and
the bookmark's deferred runs. Follow `diff-fix` on the revisions from the
earliest mutable one a reviewed run created or changed through the tip, with,
from every reviewed run combined:

- the criteria: its criteria and binding requirements, and its agreed spec from
  `Spec`, whose acceptance criteria are the complete list of what the target may
  make visible, or the visible changes `Spec` records as that list in their
  place;
- the context: its exclusions;
- the user decisions: its settled decisions, its `Decisions` not prefixed
  `diff-fix:`, and this one: fixes, conflict resolutions, and reshapes change
  only revisions a reviewed run could change; a finding or conflict in any other
  revision needs the user;
- the decisions `diff-fix` took earlier: its `Decisions` prefixed `diff-fix:`.

Record the review in this run's `run.md`, or, when reviewing a ready draft
without building, in the newest deferred run's. When the review ends `finished`,
set `Review: done` in the header of every deferred run it covered.

## Report

A stop before `run.md` exists only says why. Otherwise write `Outcome`: `done`,
`blocked`, or `stopped by user`, then append `diff-fix`'s outcome when a review
ran. After a handover, open with every choice made under it, each with the
option it rejected. Report the result, landed revisions in branch order, the
bookmark, checks, and any remaining work, conflicts, or unsettled suspected
defects, then `diff-fix`'s report, or why the review did not run. Link the run
record and agreed spec, if any. When review stays deferred, end with one line
naming the revisions a ready review would cover by the change IDs of the
earliest and the tip, with their count, the bookmark, and the branch base, and
saying that calling the draft ready reviews it.
