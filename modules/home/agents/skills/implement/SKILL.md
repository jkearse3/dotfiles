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
argument-hint: "[what to implement, or where its description lives]"
---

# Implement

Turn any description of a change into a stack of finalized, independently valid
revisions. This session coordinates: it keeps the brief list, verifies and
finalizes each revision, and asks the user. Subagents do the exploration and the
editing; if the host cannot start fresh agents, stop and report.

## Input

```text
$ARGUMENTS
```

Accept the input in whatever form it arrives: the request itself, a file, an
issue, a note, a plan, a spec, or the conversation. Take from it the outcome,
explicit criteria, exclusions, settled decisions, and binding requirements such
as constraints and prescribed implementation details, and preserve their
wording. Read a referenced artifact only as far as needed to hand it on; do not
explore the codebase here.

Require a jj repository with an empty `@` and no unrelated working changes.
Record `@-` as the stack base, establish a task-owned bookmark on `@` before the
first revision, and refer to every revision by change ID. Invoking this skill
authorizes creating and finalizing the new revisions and running `diff-fix` on
them. It authorizes nothing outside the new stack and no publication.

## Brief List

Keep a brief list in the conversation. Each brief is one revision concern: its
goal, exact targets when known, concrete changes, preserved behavior, checks
that prove it, and the briefs it depends on. Its status is `pending`, `done`
with its change ID, `skipped` with the user's reason, or `blocked` with the
question or evidence.

Every subagent receives the input's outcome, criteria, exclusions, settled
decisions, and binding requirements verbatim, plus the briefs before and after
its own. Those are earlier conclusions, reopened only when the current code
shows their reason no longer holds. Every planner also receives the `Brief Size`
rules verbatim.

## Brief Size

Give each brief one concern, and split until a further split would leave a
revision that cannot build or pass its checks alone. Every brief is safe to land
on main by itself and relies on no later brief.

- Put a behavior-preserving refactor that makes room for a change in its own
  brief before that change.
- Keep mechanical changes such as renames, moves, formatting, and dependency
  bumps apart from logic changes.
- Land internals before the brief that wires them in or exposes them.
- Give each user-visible change its own brief when it can land independently.
- Keep code, tests, documentation, and configuration with the concern that needs
  them; never split them into briefs of their own.

Recheck a brief that touches many unrelated files or mixes concerns, and split
it or state why it cannot be split.

## Loop

1. **Break down.** Dispatch a fresh planner to explore read-only: no edits, VCS
   mutation, scratch files in the repository, or delegation. It returns ordered
   briefs that produce the outcome, sized by the `Brief Size` rules. It also
   returns any question whose answer is a user-owned decision that would change
   the briefs. Ask the user those questions before implementing, and rebrief
   with the answers as settled decisions. Then show the brief list and continue
   without waiting for approval.
2. **Implement.** For the earliest `pending` brief, confirm `@` is empty and
   sits on the last finalized revision, or on the stack base for the first
   brief, then dispatch a fresh implementer with that brief. It follows
   `coding-style`, edits only the working copy, performs no VCS mutation or
   delegation, runs the brief's checks, and returns `done` with the checks run
   and a summary of what changed and why, `blocked` with the evidence or
   question, or `rebrief` with the evidence that the remaining briefs are wrong.
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
   `done` with its change ID. If it stops because the changes are not one
   coherent revision, treat that as a verification failure.
5. **Rebrief.** On a `rebrief` return, or when a landed revision shows later
   briefs are wrong, dispatch a fresh planner with the brief list and the
   evidence to revise only the `pending` briefs. A rebrief that changes the
   outcome, criteria, a settled decision, or a binding requirement needs the
   user.
6. **Ask** the user when a brief is `blocked`, and offer: decide, skip, or stop.
   A decision updates the brief and makes it `pending`. A skip makes it
   `skipped` and rebriefs the `pending` briefs that depend on it, or skips them
   too when the user says so.
7. Repeat from step 2 until no brief is `pending`.

## Converge

Once no brief is `pending` and at least one is `done`, follow `diff-fix` on the
new stack, from the stack base to the bookmark, with the input's criteria and
binding requirements verbatim as its criteria and its exclusions as context.
Pass as user decisions the input's settled decisions and every answer and ruling
the user gave during the run, including each `skipped` brief with the user's
reason. Skip this step when the user asked not to review.

## Report

Lead with the outcome: `done`, `blocked`, or `stopped by user`. Then list the
finalized revisions in order with change IDs and descriptions, the bookmark,
skipped or blocked briefs with their reasons, checks run and skipped, and the
`diff-fix` result.

## Boundaries

- Never push, publish, or mutate external systems.
- Never rewrite revisions outside the new stack.
- Never let a subagent decide a user-owned question; return it to the user.
