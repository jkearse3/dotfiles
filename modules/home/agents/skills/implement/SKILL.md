---
name: implement
description: >-
  Implements a requested change in a jj repository as a stack of finalized
  revisions, breaking the work into revision briefs and building each one
  through a fresh implementer subagent so this session's context stays small,
  then converging the stack with diff-fix. Use when the user asks to implement,
  build, or carry out a change from any input: a request, issue, plan, note, or
  spec. Not for one-off fixes to finalized revisions, read-only investigation or
  review, Git-only checkouts, or publication.
---

# Implement

Turn any description of a change into a stack of finalized, independently valid
revisions. This session coordinates: it keeps the run's state, verifies and
finalizes each revision, and asks the user. Subagents do the exploration and the
editing; if the host cannot start fresh agents, stop and report.

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
`diff-fix` on them. It authorizes nothing outside the new stack and run
directory and no publication.

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
- `Briefs`: each brief with its fields and status from `Brief List`.
- `Rebriefs`: each rebrief's trigger, evidence, and what changed, and any rewind
  with its abandoned change IDs.
- `Landed notes`: for each `done` brief, the deviations and established patterns
  later briefs must build on, from the implementer's summary.
- `Outcome`, written at the end: `done`, `blocked`, or `stopped by user`, and
  the `diff-fix` result or why it was skipped.

`implementer.md` holds the implementer rules from step 2, the path of
`briefs.md` and of the input when `Input` points to it, and the return contract.
Write it once before the first implementer, and revise it only when those rules
change.

## Brief List

Each brief is one revision concern: its goal, exact targets when known, concrete
changes, preserved behavior, checks that prove it, and the briefs it depends on.
Its status is `pending`, `done` with its change ID, `skipped` with the user's
reason, or `blocked` with the question or evidence.

Through the run directory, every subagent receives the input's outcome,
criteria, exclusions, settled decisions, and binding requirements verbatim, plus
the briefs before and after its own. Those are earlier conclusions, reopened
only when the current code shows their reason no longer holds. Implementer
prompts give the absolute paths of `briefs.md` and `implementer.md` and name the
brief instead of repeating their contents. Planner prompts give the path of
`briefs.md` for the input and brief list, and the `Brief Size` rules and
`finalize-changes`' Sequencing section verbatim inline, since no run file holds
them.

## Brief Size

Give each brief one concern, and split by concern, not by file type or layer,
until a further split would leave a revision that cannot build or pass its
checks alone. Give each user-visible change its own brief when it can land
independently. Bound and order briefs by `finalize-changes`' Sequencing section,
so every brief is safe to land on main by itself and relies on no later brief.

Recheck a brief that touches many unrelated files or mixes concerns, and split
it or state why it cannot be split.

## Loop

1. **Break down.** Dispatch a fresh planner to explore read-only: no edits, VCS
   mutation, scratch files in the repository, or delegation. It returns ordered
   briefs that produce the outcome, sized by the `Brief Size` rules. It also
   returns any question whose answer is a user-owned decision that would change
   the briefs. Ask the user those questions before implementing, record the
   answers under `Decisions during the run`, and rebrief with them as settled
   decisions. Then write the briefs to `briefs.md`, show the brief list, and
   continue without waiting for approval.
2. **Implement.** For the earliest `pending` brief, confirm `@` is empty and
   sits on the last `done` revision, or on the stack base for the first brief,
   then dispatch a fresh implementer with that brief. It follows `coding-style`,
   edits only the working copy, performs no VCS mutation or delegation, runs the
   brief's checks, and returns `done` with the checks run and a summary of what
   changed and why, `blocked` with the evidence or question, or `rebrief` with
   the evidence that the briefs, including `done` ones, are wrong.
3. **Verify.** Confirm the diff achieves the brief, changes nothing outside it,
   and passes its checks; rerun a check whose result the next decision depends
   on. Discard the attempt with `jj restore` on `@` whenever it ends without a
   verified `done`; unlike abandoning, this empties `@` in place and keeps its
   change ID and any bookmark on it. A `blocked` return then makes the brief
   `blocked`, and a `rebrief` return goes to step 5. On a first verification
   failure, dispatch one fresh implementer with the failure as evidence in the
   emptied `@`; a second makes the brief `blocked`.
4. **Finalize.** Follow `finalize-changes` for the verified working changes with
   single-revision intent, passing the implementer's summary as context for the
   description and moving the task bookmark to the new tip. Mark the brief
   `done` with its change ID and add its entry to `Landed notes`. If it stops
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

## Converge

Once no brief is `pending` and at least one is `done`, follow `diff-fix` on the
new stack, from the stack base to the bookmark, with the input's criteria and
binding requirements verbatim as its criteria and its exclusions as context.
Pass as user decisions the input's settled decisions and, from `briefs.md`,
every answer and ruling the user gave during the run, including each `skipped`
brief with the user's reason. Skip this step when the user asked not to review.

## Report

Write `Outcome` to `briefs.md`. Then lead the report with the outcome: `done`,
`blocked`, or `stopped by user`. List the finalized revisions in order with
change IDs and descriptions, the bookmark, any rewind with its evidence and
abandoned revisions, skipped or blocked briefs with their reasons, checks run
and skipped, the `diff-fix` result, and the run directory's absolute path.

## Boundaries

- Never push, publish, or mutate external systems.
- Never rewrite revisions outside the new stack.
- Besides the new stack and the session scratchpad, write only the
  `.agent/implement/` store, whose `.gitignore` `prepare-run.sh` creates, and
  this run's directory. Never track, publish, or delete them.
- Never let a subagent decide a user-owned question; return it to the user.
