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
  next reviewer or fixer receives from the ledger, including `run.criteria`.
  Finding IDs restrict the fixer's `open` findings to those named. Each finding
  appears once: a listed finding carries its own decisions, and `decided` holds
  only decided findings no other list includes. Pass it unchanged; never trim or
  paraphrase it.

| Event        | Fields                                                                      | Record when                                            |
| ------------ | --------------------------------------------------------------------------- | ------------------------------------------------------ |
| `run`        | `target` (full change ID array), `base`, `criteria`, and any `bookmark`     | once, at preflight                                     |
| `review`     | `revisions`, `verdict` (`pass`, `non-pass`, `blocked`)                      | each review returns                                    |
| `finding`    | `owner`, `category`, `priority`, `location`, `mechanism`, `status`          | a reviewer raises a new finding                        |
| `status`     | `id`, `status`, `evidence`                                                  | a finding changes status outside a landing or decision |
| `attempt`    | `id`, `outcome` (`fixed`, `rejected`, `escalated`, `unverified`), `summary` | a fixer returns, or verification fails a claimed fix   |
| `land`       | `from`, `to` (commit IDs), `findings`                                       | a fix or resolution lands; its findings become `fixed` |
| `checkpoint` | `summary`                                                                   | the user answers an escalation                         |
| `decision`   | `decision`, and `id` with `effect` (`settled`, `open`) for one finding      | the user decides a finding, or up front                |

Owners are full change IDs from `run.target`; `record` and `context fix` reject
any other owner. Events may carry extra fields such as `suggested` or `checks`.
`run.criteria` holds the criteria and context verbatim, or `none` when none were
declared.

### Finding Statuses

Findings are `open`, `fixed`, `disputed`, `pending-decision`, or `settled`, and
change status only as below; `record` rejects any other change. A finding a
decision opened carries a user request, so a reviewer or fixer never settles or
disputes it.

| From               | When                                                               | To                 |
| ------------------ | ------------------------------------------------------------------ | ------------------ |
| new                | a `design` or `question` finding                                   | `pending-decision` |
| new                | any other finding                                                  | `open`             |
| `open`             | re-raised, or declined when a decision opened it                   | `open`             |
| `open`             | declined with a reason, when no decision opened it                 | `settled`          |
| `open`             | its fix lands (`land`)                                             | `fixed`            |
| `open`             | an unverified fix, or a rejection without concrete evidence        | `open`             |
| `open`             | an evidenced rejection, when no decision opened it                 | `disputed`         |
| `open`             | an escalation, or an evidenced rejection when a decision opened it | `pending-decision` |
| `fixed`            | re-raised                                                          | `pending-decision` |
| `disputed`         | re-raised                                                          | `pending-decision` |
| `disputed`         | not re-raised                                                      | `settled`          |
| `settled`          | re-raised                                                          | `pending-decision` |
| `settled`          | its evidence moved before a review                                 | `disputed`         |
| `pending-decision` | re-raised                                                          | `pending-decision` |
| any                | the user decides it, or a standing decision covers it (`decision`) | the effect         |

Any status not listed for a trigger stays as it is; in particular a `fixed`
finding stays `fixed` when not re-raised.

## Loop

Repeat until a review passes or the run stops:

1. **Review.** Re-resolve the target's change IDs to current commits, then
   dispatch a fresh reviewer with the request in **Review Request**. Before
   sending, confirm each settled conclusion's evidence has not moved; record one
   whose evidence moved as `disputed`, citing the move, so the reviewer
   arbitrates it. `pass` ends the loop; `blocked` stops it and is reported.
2. **Triage.** Record each new finding with the category, owner, and mechanism
   the reviewer reported; never infer them in this session. Resolve the reported
   owner with jj to its full change ID in `run.target`. Return an incomplete
   review to that reviewer: a finding without one `diff-review` category, an
   owner, or a mechanism, a finding whose owner does not resolve into the
   target, or a carried `open` finding neither re-raised nor declined with a
   reason. Match a re-raised finding to its entry by mechanism and location
   rather than wording; a finding against the change a landed fix made re-raises
   that fix's finding. Apply **Finding Statuses**, recording a covering standing
   decision as a `decision` event with the finding's `id` and `effect` that
   cites it.
3. **Escalate** when a trigger in **Escalation** holds, before fixing, so a
   paused round shows its findings as the review left them.
4. **Fix** each owning revision with `open` findings, earliest first, as below.

Run subagents sequentially; never let two write concurrently. Delegates may not
delegate further.

### Review Request

Send every reviewer the same request:

- follow the `diff-review` skill, read-only: no file edits, no VCS mutation, no
  scratch files inside the repository, and no further delegation;
- the target's full change IDs, current commits, any bookmark, and the base;
- `context review` unchanged. It holds the criteria, settled findings as prior
  independent conclusions not to re-raise unless their evidence moved, disputed
  findings as claims to arbitrate, `open` findings carried from an earlier round
  as claims to confirm, and user decisions as the user's chosen design;
- return the verdict and, per finding, exactly one `diff-review` category, a
  priority, a `file:line` location, the causal mechanism with a failure
  scenario, the owning revision (the change ID of the earliest target revision
  whose diff introduces the defect), and any suggested fix;
- re-raise each carried `open` finding it confirms and give a reason for each it
  declines;
- list the checks run and their results.

### Fix

1. Create a fresh empty child of the owning revision as the working copy.
2. Dispatch a fresh fixer with the target description and `context fix <owner>`
   unchanged: the criteria, that revision's `open` findings with their attempt
   history, every `pending-decision` finding, settled findings, and user
   decisions. It follows the `coding-style` skill, edits only the working copy,
   formats and checks only the files it touched, keeps the rules or behavior it
   changes consistent with the code around them, performs no VCS mutation, and
   returns per finding one of:
   - `fixed`, with the checks run and their results;
   - `rejected`, with concrete evidence such as file references, a trace, or a
     check result;
   - `escalated`, with the decision it needs from the user, including when its
     fix depends on a `pending-decision` finding.

   It also reports whether its changes make the owning revision's description
   inaccurate and, when they do, returns the replacement text. A finding about
   the description itself is fixed the same way.

3. Verify the fixer's diff: it addresses only its findings, stays within the
   target's concern, and passes proportionate checks. Record an `attempt` for
   each finding; an unverified fix or a rejection without concrete evidence
   stays `open`. When only some findings verify, keep the verified changes and
   dispatch a fresh fixer on the same working copy with
   `context fix <owner> <id>...` naming the rest, marking the verified changes
   as kept. Re-dispatch at most once per batch; findings still `open` after it,
   or when none verify, carry to the next full review as claims to confirm.
   Before landing, every change in the working copy must be verified; revert
   changes for findings not landing, and skip landing only when neither a change
   nor a verified description replacement remains.
4. Land the verified change with
   `scripts/land.sh --workspace <workspace> <ledger> <owner> <id>...`, naming
   the findings it fixes. For a verified description replacement, compose and
   validate it as `finalize-changes` describes, write it to a file outside the
   repository, and add `--description-file <path>`; a description-only fix lands
   the same way from the empty working copy. Before mutating, the script checks
   the owner, that each named finding is open and owned by it, and that the
   landing changes something; it then squashes the working copy into the owner,
   confirms the owner holds exactly the verified tree and is not conflicted,
   records the `land`, and prints each conflicted descendant as a
   `target-conflict` or `outside-conflict` line. Stop when it fails.
5. Resolve each `target-conflict` revision, earliest first, before the next fix
   or review. Create a fresh empty child of it as the working copy and dispatch
   a fresh fixer with the request in **Resolution Request**. Verify that no
   conflict remains in the working copy, the resolution changes nothing beyond
   carrying the landed fix into the revision, and proportionate checks pass;
   stop when it fails. Land it with `scripts/land.sh` naming the conflicted
   revision as `<owner>` and no findings, since the landed fix already marked
   them `fixed`, and resolve any `target-conflict` it reports in turn. Then stop
   when an `outside-conflict` revision remains conflicted.
6. Run `jj new <target tip>` so an empty working copy sits above the target
   before the next review, and record each rejection and escalation through
   **Finding Statuses**.

### Resolution Request

Send every conflict resolver the same request:

- the fixer rules from **Fix** step 2: follow `coding-style`, edit only the
  working copy, format and check only touched files, and perform no VCS
  mutation;
- the conflicted revision's change ID and description, and its pre-rebase commit
  so its intended diff can be read;
- the landed fix: its owning revision, its `from` and `to` commits from the
  `land` event, and its findings from `state`;
- resolve every conflict so the revision keeps its own intent and carries the
  landed fix's intent, and change nothing else;
- return `fixed` with the checks run, or `escalated` with the decision needed
  when the two intents cannot both hold, and report whether the revision's
  description stays accurate, with replacement text when it does not.

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
