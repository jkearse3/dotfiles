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
fresh reviewer and fresh fixer subagents. This session orchestrates: it owns the
ledger, verifies and lands fixes, and escalates to the user. It never reviews or
fixes findings itself.

## Input

Infer from the request and conversation:

- **Target:** the locally available revisions to converge, as `diff-review`
  would resolve them. Ask rather than guess an ambiguous target or base.
- **Criteria and context:** declared criteria, focus areas, non-goals, and known
  issues, passed unchanged to every review.
- **Standing decisions:** decisions the user makes up front for this run, such
  as "fix design findings too" or "leave the naming as is". Triage applies them
  instead of asking.

Invoking this skill authorizes squashing fixes and conflict resolutions into the
target's mutable revisions and rebasing their descendants. It authorizes nothing
outside the target and no publication.

## Preflight

1. Require a jj repository; stop otherwise. Record the target by its full change
   IDs, and its bookmark when named, which survive squashes. Apply `diff-review`
   target preconditions: described revisions and an empty `@` above the
   checked-out target.
2. Stop when `<target> & immutable()` is non-empty; trunk is never rewritten.
3. List descendants outside the target that squashes will rebase, for the
   report.
4. Confirm the host can start a fresh agent with its own context, such as a
   subagent or a managed teammate. If it cannot, stop and report; never fall
   back to reviewing or fixing in this session.
5. Reserve the ledger with
   `scripts/prepare-ledger.sh --workspace <workspace> <target-slug>`, passing
   the absolute root of the jj workspace holding the target. Invoke the script
   by its path; it is independent of the current working directory. It reserves
   an empty `.jsonl` file in the ignored `.agent/diff-fix/` store of that
   workspace and prints its absolute path. Stop and report on any failure.
   Record the `run` event and each standing decision, keep the ledger after the
   run, and restate its path in each status update so it survives context loss.

`tests/ledger-scripts.sh` is maintainer validation, not part of normal skill
operation. Run it only when modifying this skill or when the user explicitly
requests that test.

## Ledger

The ledger is an append-only event log, written only through
`scripts/ledger.sh record <ledger> <event>` with the event as one JSON object on
stdin; never edit the file by hand. The script validates the event, appends it,
and prints the assigned finding ID for a `finding` event. Read it through two
views:

- `scripts/ledger.sh state <ledger>`: every finding with its attempts and
  decisions, standing decisions, review counts, and landings. Read it to resume
  after context loss.
- `scripts/ledger.sh context <ledger> review` and
  `scripts/ledger.sh context <ledger> fix <owner> [<id>...]`: exactly what the
  next reviewer or fixer receives from the ledger. Finding IDs restrict the
  fixer's `open` findings to those named. Pass it unchanged.

| Event        | Fields                                                                      | Record when                                          |
| ------------ | --------------------------------------------------------------------------- | ---------------------------------------------------- |
| `run`        | `target` (full change ID array), `base`, `criteria`, and any `bookmark`     | once, at preflight                                   |
| `review`     | `revisions`, `verdict` (`pass`, `non-pass`, `blocked`)                      | each review returns                                  |
| `finding`    | `owner`, `category`, `priority`, `location`, `mechanism`, `status`          | a reviewer raises a new finding                      |
| `status`     | `id`, `status`, `evidence`                                                  | a finding changes status outside a decision          |
| `attempt`    | `id`, `outcome` (`fixed`, `rejected`, `escalated`, `unverified`), `summary` | a fixer returns, or verification fails a claimed fix |
| `land`       | `from`, `to` (commit IDs), `findings`                                       | a fix lands                                          |
| `checkpoint` | `summary`                                                                   | the user answers an escalation                       |
| `decision`   | `decision`, and `id` with `effect` (`settled`, `open`) for one finding      | the user decides a finding, or up front              |

Finding statuses are `open`, `fixed`, `disputed`, `pending-decision`, and
`settled`. Owners are full change IDs from `run.target`; `record` and
`context fix` reject any other owner. Events may carry extra fields such as
`suggested` or `checks`. `run.criteria` holds the criteria and context verbatim,
or `none` when none were declared.

## Loop

Repeat until a review passes or the run stops:

1. **Review.** Re-resolve the target's change IDs to current commits, then
   dispatch a fresh reviewer that follows the `diff-review` skill with the full
   target, `run.criteria` from the ledger state, and `context review`. That
   context holds settled findings as prior independent conclusions not to
   re-raise unless their evidence moved, disputed findings as claims to
   arbitrate, `open` findings carried from an earlier round as claims to
   confirm, and user decisions. Ask the reviewer to re-raise each carried `open`
   finding it confirms and give a reason for each it declines, and to state, for
   each finding, its causal mechanism and its owning revision: the change ID of
   the earliest target revision whose diff introduces the defect. Before
   sending, confirm each settled conclusion's evidence has not moved; record one
   whose evidence moved as `disputed`, citing the move, so the reviewer
   arbitrates it and triage applies. `pass` ends the loop; `blocked` stops it
   and is reported.
2. **Triage.** Record each finding with the owner and mechanism the reviewer
   reported; never infer them in this session. Resolve the reported owner with
   jj to its full change ID in `run.target`. Treat a finding without an owner or
   mechanism, a finding whose owner does not resolve into the target, or a
   carried `open` finding neither re-raised nor declined with a reason, as an
   incomplete review to return to that reviewer. Match a re-raised finding to
   its entry by mechanism and location rather than wording:
   - a re-raised `fixed`, `disputed`, or `settled` finding becomes
     `pending-decision`, and a re-raised `pending-decision` or `open` finding
     keeps its status;
   - a `disputed` finding the reviewer did not re-raise becomes `settled`, and
     so does an `open` one the reviewer declined with a reason, citing it,
     unless a decision opened it;
   - a finding a standing decision covers takes that decision's effect,
     `settled` to leave the code as is or `open` to change it, recorded as a
     `decision` event with the finding's `id` and `effect` that cites the
     standing decision;
   - any other `design` or `question` finding becomes `pending-decision`;
   - everything else is `open`.
3. **Escalate** when a trigger in **Escalation** holds, before fixing, so a
   paused round shows its findings as the review left them.
4. **Fix** each owning revision with `open` findings, earliest first, as below.

Run subagents sequentially; never let two write concurrently. Delegates may not
delegate further.

### Fix

1. Create a fresh empty child of the owning revision as the working copy.
2. Dispatch a fresh fixer with the target description and `context fix <owner>`:
   that revision's `open` findings with their attempt history, every
   `pending-decision` finding, settled findings, and user decisions. It follows
   the `coding-style` skill, edits only the working copy, formats and checks
   only the files it touched, performs no VCS mutation, and returns per finding
   one of:
   - `fixed`, with the checks run and their results;
   - `rejected`, with concrete evidence such as file references, a trace, or a
     check result;
   - `escalated`, with the decision it needs from the user, including when its
     fix depends on a `pending-decision` finding.

   It also reports whether its changes make the owning revision's description
   inaccurate and, when they do, returns the replacement text. A finding about
   the description itself is fixed the same way.

3. Verify the fixer's diff: it addresses only its findings, stays within the
   target's concern, and passes proportionate checks. Treat a rejection without
   concrete evidence, or an unverified fix, as still `open`, and record the
   failed attempt. When only some findings verify, keep the verified changes and
   dispatch a fresh fixer on the same working copy with
   `context fix <owner> <id>...` naming the rest, marking the verified changes
   as kept. Re-dispatch at most once per batch; findings still `open` after it,
   or when none verify, carry to the next full review as claims to confirm.
   Before landing, every change in the working copy must be verified; revert
   changes for findings still `open`, `disputed`, or `pending-decision`, and
   skip landing only when neither a change nor a verified description
   replacement remains.
4. Land the fix through `finalize-changes`: squash any change into the owning
   revision, apply any verified description replacement, keep the description
   accurate, and inspect the rebased descendants. A description-only fix lands
   the same way and is recorded as a landing. Stop when the landing conflicts
   the owning revision. Leave an empty working copy above the target tip before
   the next review.
5. Resolve conflicts the landing leaves in descendant target revisions, earliest
   first, before the next fix or review. Create a fresh empty child of the
   conflicted revision and dispatch a fresh fixer under the rules above with
   that revision's description and the landed fix's findings and diff. It
   resolves the conflict so the revision keeps its own intent and carries the
   landed fix's intent. Verify that the conflict is gone, the resolution changes
   nothing else, and proportionate checks pass; stop when it fails. Squash it
   into the conflicted revision through `finalize-changes`, record it as a
   landing of the same findings, and repeat for any conflicted descendant. Then
   stop when a descendant outside the target remains conflicted.
6. Record each attempt, any landing, and the resulting status: `fixed`,
   `disputed` for evidenced rejections, or `pending-decision` for escalations
   and for evidenced rejections of a finding a decision opened, so the user
   weighs the fixer's evidence.

## Escalation

Check after triage and pause to ask the user when either holds:

- ten full reviews since the last user checkpoint have not passed
  (`full_reviews_since_checkpoint` in the ledger state);
- the review did not pass and no `open` findings remain, so the round has
  nothing to fix: its unresolved findings all await a decision, or the review
  recorded none, such as an unsatisfied criterion without a correctable defect.

Present the findings needing a decision, their attempt history, and the review's
unsatisfied criteria. Offer: decide, continue for more rounds, or stop. A
decision to leave the code as is becomes `settled`; a decision or user request
calling for a change becomes an `open` finding that carries it to the fixer.
Record the checkpoint and each decision; a request not tied to a finding is
first recorded as a `finding`. Each checkpoint resets the full-review count.

## Report

Lead with the outcome: `pass`, `stopped by user`, or `blocked`. Then include:

- final revision IDs, rewritten revisions, and rebased descendants outside the
  target;
- full reviews run;
- fixed, disputed, and user-settled findings, and any unresolved findings;
- checks run and skipped, with reasons.

## Boundaries

- Never push, publish, or mutate external systems.
- Never rewrite or move references outside the target, except rebasing its
  descendants.
- Never lower the pass bar, edit criteria, or phrase review requests to suppress
  findings.
