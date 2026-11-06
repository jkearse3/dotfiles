---
name: implement
description: >-
  Implements a requested change in a jj repository as a stack of finalized
  revisions, breaking the work into revision briefs and building each one
  through a fresh implementer subagent so this session's context stays small,
  then refining the stack with diff-refine and converging it with diff-fix. Use
  when the user asks to implement, build, or carry out a change from any input:
  a request, issue, plan, note, or spec. Not for one-off fixes to finalized
  revisions, read-only investigation or review, Git-only checkouts, or
  publication.
---

# Implement

Turn any description of a change into a stack of finalized, independently valid
revisions. This session coordinates: it keeps the run's state, judges and
finalizes each revision, and asks the user. Subagents do the exploration, the
editing, and the checks; if the host cannot start fresh agents, stop and report.

## Input

Take what to implement from the user's request and context, in whatever form it
arrives: the request itself, a file, an issue, a note, a plan, a spec, or the
conversation. Draw from it the outcome, explicit criteria, exclusions, settled
decisions, and binding requirements such as constraints and prescribed
implementation details, and preserve their wording. Read a referenced artifact
only as far as needed to hand it on; do not explore the codebase here.

Require a jj repository with an empty `@` and no unrelated working changes.
Record `@-` as the stack base. Then, before the first planner, run
`scripts/prepare-run.sh --workspace <workspace-root> <slug>` by its path,
passing the workspace's absolute root and a slug of a few words for the outcome.
It is independent of the current working directory, resolves the canonical root,
prepares the ignored `.agent/implement/` store there, and reserves a new
`<timestamp>-<slug>/` run directory. It succeeds with exit status 0 and prints
the directory's absolute path on stdout; a jj `No matching entries` warning on
stderr is benign. On any other status, such as 3 for ambiguous storage, stop and
report its error; never fall back to the scratchpad or the workspace. Write
`briefs.md`'s header and `Input` there. Establish a task-owned bookmark on `@`
before the first revision and record it in the header. Refer to every revision
by change ID.

Invoking this skill authorizes creating and writing this run directory, and
creating, finalizing, rewinding, and abandoning the new revisions and running
`diff-refine` and `diff-fix` on them. It authorizes nothing outside the new
stack and run directory and no publication.

## Run Directory

The run directory holds the run's state and is kept after the run, whatever its
outcome. `briefs.md` is the source of truth: after compaction, or whenever
memory and the file could differ, reread it before acting. This session is the
only writer; subagents read the directory and never write it. Write it before
each dispatch that depends on it and after each status change, decision,
rebrief, rewind, or bookmark change. Per-revision throwaway files, such as
description drafts and check logs, stay in the session scratchpad.

`briefs.md` holds, in order:

- A header: the workspace's absolute path, the stack base change ID, the task
  bookmark, and the input source: a file's absolute path, an issue ID or URL, or
  `conversation`.
- `Input`: the outcome, criteria, exclusions, settled decisions, and binding
  requirements verbatim. Only when the input is a file under the canonical
  root's `.agent/`, give instead its absolute path and which of its sections map
  to each.
- `Decisions during the run`: each user answer and ruling, and accepted rebrief
  evidence, dated.
- `Briefs`: each brief with its fields and status from `Brief List`, and, for a
  staged brief, each stage's recorded commit ID and handoff from step 2.
- `Rebriefs`: the plan check's gaps, or that it found none; each rebrief's
  trigger, evidence, and what changed; and any rewind with its abandoned change
  IDs.
- `Landed notes`: for each `done` brief, the deviations and established patterns
  later briefs must build on, from the implementer's summary, the symbol changes
  from its `done` return, and each check result accepted at Verify with its
  exact command, its result, its reported commit ID (the entry commit), and the
  finalized change ID.
- `Refine`, written when Refine ends: applied proposals, restored ones with
  their failure evidence, unchecked revisions, and notes; or why it was skipped;
  or the state `diff-refine` reported when it stopped, then the recovery.
- `Outcome`, written at the end: `done`, `blocked`, or `stopped by user`; the
  Refine result from `Refine`, adding the declined proposals recorded under
  `Decisions during the run`; and the `diff-fix` result or why it was skipped.

`implementer.md` holds the implementer rules from step 2, including the rule to
read each run file and the input once, the path of `briefs.md` and of the input
when `Input` points to it, and the return contract, including the `stage-done`
return of a staged brief's non-final stage. Write it once before the first
implementer, and revise it only when those rules change.

## Brief List

Each brief is one revision concern: its goal, exact targets when known, concrete
changes, preserved behavior, checks that prove it, the briefs it depends on,
and, for a staged brief, `Stages`: its ordered stages, each with its scope, the
contract it hands to the next stage, and the checks it can pass alone. A brief
without `Stages` is one stage. Its status is `pending`, `done` with its change
ID, `skipped` with the user's reason, or `blocked` with the question or
evidence.

Through the run directory, every subagent receives the input's outcome,
criteria, exclusions, settled decisions, and binding requirements verbatim, plus
the briefs before and after its own. Those are earlier conclusions, reopened
only when the current code shows their reason no longer holds. Implementer
prompts give the absolute paths of `briefs.md` and `implementer.md` and name the
brief instead of repeating their contents. Planner prompts give the path of
`briefs.md` for the input and brief list, and the `Brief Size` and `Stages`
rules and `finalize-changes`' Sequencing section verbatim inline, since no run
file holds them.

## Brief Size

Give each brief one concern, and split by concern, not by file type or layer,
until a further split would leave a revision that cannot build or pass its
checks alone. Give each user-visible change its own brief when it can land
independently. Bound and order briefs by `finalize-changes`' Sequencing section,
so every brief is safe to land on main by itself and relies on no later brief.

Recheck a brief that touches many unrelated files or mixes concerns, and split
it or state why it cannot be split.

## Stages

Divide a brief's work into ordered stages at every contract boundary: a point
where the next stage needs only the interface the earlier stage produced, such
as changed types, signatures, schema, or behavior, not the code it read to
produce it. A typical division has three stages: change the core contract and
its own tests; migrate its consumers; update repository text such as docs,
messages, and guidance. Stage whenever such a boundary exists, except when all
parts of the brief need the same code in view, or when an earlier stage could be
judged only by what a later stage produces; leave such a brief unstaged.

Each stage is built by its own fresh implementer in the same `@`, in order, and
all stages together make the brief's one revision. Give an earlier stage the
narrower checks its part can pass alone, since consumers may not build until a
later stage migrates them; only the final stage must pass the brief's checks.

## Loop

1. **Break down.** Dispatch a fresh planner to explore read-only: no edits, VCS
   mutation, scratch files in the repository, or delegation. It returns ordered
   draft briefs that produce the outcome, sized by the `Brief Size` rules and
   staged by the `Stages` rules, and any question whose answer is a user-owned
   decision that would change the briefs. Write the draft briefs to `briefs.md`
   and check them before asking the user anything.

   Dispatch one fresh checker under the planner's read-only limits. Its prompt
   gives the absolute path of `briefs.md`, and of the input when `Input` points
   to it, and `finalize-changes`' Sequencing section and the `Stages` rules
   verbatim; it may read the workspace to confirm targets. It checks that every
   input criterion is proven by some brief's checks; that every brief is
   independently valid and ordered by Sequencing, relying on no later brief;
   that no brief contradicts an exclusion, settled decision, or binding
   requirement; that each brief is self-contained enough for a fresh implementer
   to build without guessing; and that every stage boundary is a contract
   boundary and every stage is buildable by a fresh implementer from the brief
   and the contracts earlier stages declare in `Stages`. It does not judge or
   attack the approach, which the run treats as settled. It returns each gap
   with the brief and input item at fault, the failed check, and whether it
   needs a user-owned decision, or that it found none; record that result under
   `Rebriefs`.

   Then settle the planner's questions and the checker's gaps with one ask and
   one revision. Merge a gap that a planner question already covers into that
   question. Ask the user the planner's questions and the gaps that need a
   user-owned decision together, in one ask before implementing, and record the
   answers under `Decisions during the run`. Give those answers, as settled
   decisions, and the remaining gaps to one fresh planner, prompted as in Break
   down, to revise the briefs once, and update `briefs.md` in place. With no
   questions and no gaps, skip the ask and the revising planner; with gaps but
   none needing the user, skip the ask and give the revising planner the gaps.
   Do not run the checker again: confirm the revision closes each gap and
   reflects each answer. For any gap it leaves open or returns as unresolvable,
   and any new user-owned question it returns, ask the user before implementing
   and offer decide, skip the affected brief, or stop, as step 6 does, recording
   the answer under `Decisions during the run`. Then show the brief list and
   continue without waiting for approval.

2. **Implement.** For the earliest `pending` brief, confirm `@` is empty and
   sits on the last `done` revision, or on the stack base for the first brief,
   then dispatch a fresh implementer with that brief. It reads `implementer.md`,
   `briefs.md`, and the input when `Input` points to it once each, whole, in
   non-overlapping ranges when a file is too large for one read, and rereads one
   only after its context is compacted or when told the file changed. It follows
   `coding-style`, edits only the working copy, performs no VCS mutation or
   delegation, runs the brief's checks, and returns `done` with each check's
   exact command, its result, and `@`'s commit ID read with
   `jj log -r @ --no-graph -T commit_id` immediately before running it, a
   summary of what changed and why, and its symbol changes: each symbol the
   revision renamed, moved, or removed that a later brief names, or that there
   are none; `blocked` with the evidence or question; or `rebrief` with the
   evidence that the briefs, including `done` ones, are wrong.

   Build a staged brief one stage at a time, in order, in the same `@`,
   confirming `@` as above only before the first stage. Before each stage,
   record under the brief in `briefs.md` `@`'s commit ID, read with
   `jj log -r @ --no-graph -T commit_id` so the working copy is snapshotted
   first. Then dispatch a fresh implementer under the rules above, naming the
   brief and the stage; it reads earlier stages' handoffs from `briefs.md`,
   builds only its stage, and runs that stage's checks. A non-final stage
   returns `stage-done` with what changed, the contract it hands on, its symbol
   changes, and its checks reported as `done` reports them, or `blocked` or
   `rebrief` as above; the final stage returns `done`, whose symbol changes
   cover every stage. A non-final stage that returns `done`, or a final stage
   that returns `stage-done`, is a stage failure. After each `stage-done`, judge
   `jj diff --from <recorded commit ID>` against the stage's scope and its
   reported checks, dispatching a rerun agent as in Verify when a report is
   missing, inconsistent with the diff, or doubtful. A diff outside the stage's
   scope or a failing stage check is a stage failure, handled in Verify.
   Otherwise record the `stage-done` return under the brief as the stage's
   handoff and continue with the next stage. When the whole brief resets,
   through a `blocked` or `rebrief` return or second failure that restores its
   `@`, a rewind, or a return to `pending`, mark its recorded stage commit IDs
   and handoffs superseded so later stage implementers ignore them. Redoing a
   stage supersedes nothing recorded before that stage.

3. **Verify.** Judge from the diff and the implementer's reported checks that
   the diff achieves the brief, changes nothing outside it, and passes the
   brief's checks; this session runs no checks. When a check report is missing,
   inconsistent with the diff, or doubtful, dispatch a fresh agent to rerun the
   named checks and return each command, its result, and `@`'s commit ID read
   with `jj log -r @ --no-graph -T commit_id` immediately before running it. It
   edits no files beyond what the checks themselves write, performs no VCS
   mutation or delegation, and keeps scratch files in the session scratchpad. A
   check failing in its rerun is a verification failure. If the rerun changed
   the working copy, such as through a formatter run as a check, judge the diff
   again before finalizing. When the diff is verified, keep each accepted
   check's exact command, result, and reported commit ID. The accepted results
   are the brief's checks as the implementer reported them, or as the rerun
   agent returned them when a rerun replaced them; a non-final stage's narrower
   checks never count. Discard the attempt with `jj restore` on `@` whenever it
   ends without a verified `done`; unlike abandoning, this empties `@` in place
   and keeps its change ID and any bookmark on it. A `blocked` return then makes
   the brief `blocked`, and a `rebrief` return goes to step 5. On a first
   verification failure, dispatch one fresh implementer with the failure as
   evidence in the emptied `@`; a second makes the brief `blocked`.

   A staged brief is verified once, after its final stage returns `done`, and
   has one retry budget for its stage failures and verification failures
   together. On a first stage failure, run
   `jj restore --from <the stage's recorded commit ID>` to drop that stage's
   work, then dispatch one fresh implementer to redo that stage with the failure
   as evidence. On a first verification failure after the final stage, dispatch
   one fresh implementer on the existing working copy with the whole brief,
   every stage handoff, and the failure as evidence; it returns `done` or one of
   the other returns as above. A second failure of either kind restores `@` and
   makes the brief `blocked`. A `blocked` or `rebrief` return from any stage
   restores `@` and is handled as for an unstaged brief.

4. **Finalize.** Follow `finalize-changes` for the verified working changes with
   single-revision intent, passing the implementer's summary, and for a staged
   brief every stage handoff, as evidence of what changed and why, never as text
   to copy, and moving the task bookmark to the new tip. Compose the description
   from the diff under `finalize-changes`'
   `references/revision-descriptions.md`; it must not mention brief names or
   numbers, `briefs.md`, rebriefs, landed notes, check logs, planners,
   implementers, checkers, or the run directory. Mark the brief `done` with its
   change ID and add its entry to `Landed notes`, recording the implementer's
   symbol changes and the check results Verify accepted there. If it stops
   because the changes are not one coherent revision, treat that as a
   verification failure.
5. **Rebrief.** On a `rebrief` return, or when a landed revision shows the
   briefs are wrong, dispatch a fresh planner with `briefs.md` and the evidence
   to revise the `pending` briefs, and update them in `briefs.md` in place. When
   the evidence shows a `done` revision took the wrong path, it also returns the
   earliest such brief, and this session rewinds: make that brief and every
   later `done` brief `pending` with its revised content and old change ID,
   rebase `@` onto the last remaining `done` revision or the stack base with
   `jj rebase -r @ -d <rev>`, and move the task bookmark back to that revision,
   or to `@` when no `done` revision remains, with `--allow-backwards`. Record
   the rebrief and any rewind under `Rebriefs`. Implementers may read the old
   revisions as reference; abandon them before converging, or report them if the
   run ends first. Show the revised brief list and continue without waiting for
   approval. A rebrief that changes the outcome, criteria, a settled decision,
   or a binding requirement needs the user.
6. **Ask** the user when a brief is `blocked`, and offer: decide, skip, or stop.
   A decision updates the brief and makes it `pending`. A skip makes it
   `skipped` and rebriefs the `pending` briefs that depend on it, or skips them
   too when the user says so. Record the decision or skip under
   `Decisions during the run`.
7. Repeat from step 2 until no brief is `pending`.

## Refine

Once no brief is `pending`, at least one is `done`, and `briefs.md` has no
`Refine` entry, follow `diff-refine` on the new stack, from the stack base to
the bookmark. Pass as caller context:

- as constraints proposals must respect, the input's criteria, exclusions,
  settled decisions, and binding requirements, and `Decisions during the run`;
- each `done` brief's checks as its revision's checks, stated as passed at
  Verify;
- the standing choice "apply every proposal that needs no user decision; ask
  about `needs-decision` proposals in one batch";
- that this session reviews the target next, so `diff-refine` skips its Check.

When `diff-refine` asks about `needs-decision` proposals, ask the user once,
giving each its question and recommended answer and offering apply or skip per
proposal, or stop the run. Record the answers under `Decisions during the run`,
each declined proposal with its location, lens, owning revision, and proposed
shape. `diff-refine`'s appliers make every edit; this session edits no files
here.

On `completed`, record the result under `Refine` in `briefs.md`, then continue
to Converge. On `stopped`, record the state `diff-refine` reports under `Refine`
and ask the user to recover it, by repairing it or authorizing a named recovery,
or to stop the run. After a recovery, record it under `Refine` and continue to
Converge; never converge on unrecovered state. Skip this step when the user
asked not to refine or not to review, and record why under `Refine`.

## Converge

Once Refine completes, is recovered, or is skipped, and at least one brief is
`done`, follow `diff-fix` on the new stack, from the stack base to the bookmark,
with the input's criteria and binding requirements verbatim as its criteria and
its exclusions as context. Pass as user decisions the input's settled decisions
and, from `briefs.md`, every answer and ruling the user gave during the run,
including each `skipped` brief with the user's reason and each proposal the user
declined during Refine. Pass each `restored` proposal with its failure evidence
as context, without labeling it declined or decided. Pass every check result in
`Landed notes`, with its reported commit ID and change ID, as check evidence.
Skip this step when the user asked not to review.

## Report

Write `Outcome` to `briefs.md`. Then lead the report with the outcome: `done`,
`blocked`, or `stopped by user`. List the finalized revisions in order with
change IDs and descriptions, the bookmark, any rewind with its evidence and
abandoned revisions, skipped or blocked briefs with their reasons, checks run
and skipped, the Refine result with its declined and restored proposals, the
`diff-fix` result, and the run directory's absolute path.

## Boundaries

- Never push, publish, or mutate external systems.
- Never rewrite revisions outside the new stack.
- Besides the new stack and the session scratchpad, write only the
  `.agent/implement/` store, whose `.gitignore` `prepare-run.sh` creates, and
  this run's directory. Never track, publish, or delete them.
- Never let a subagent decide a user-owned question; return it to the user.
