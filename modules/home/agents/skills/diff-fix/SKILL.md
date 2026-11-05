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

Drive a finalized jj target to a literal full `diff-review` `pass` by
alternating reviews by a fresh reviewer and verifier with one fresh fixer per
round. This session coordinates: it keeps the findings list, coordinates each
review, verifies and lands fixes, and asks the user. It never reviews or fixes
itself beyond coordinating `diff-review`; if the host cannot start fresh agents,
stop and report.

## Target

Resolve the target as `diff-review` does, and require a jj repository, no
`<target> & immutable()` revisions, and an empty `@` above the target. Record
any bookmark name, and refer to the target and every owning revision by change
ID, never commit ID, because each squash rewrites commits. The exceptions are
the tip commit ID step 1 records before each review, which identifies the
reviewed tree after squashes rewrite the tip, and the commit IDs step 4 records
before a reshape.

Take the declared criteria, context, and any user decisions from the request.
Invoking this skill authorizes squashing fixes into target revisions and
rebasing their descendants, and a user decision to reshape the target authorizes
that reshape. It authorizes nothing outside the target and no publication.

## Findings

Keep a findings list in the conversation. Each finding has its mechanism, its
location from the latest review, its owning revision, a status (`open`, `fixed`,
`settled`, or `needs-decision`), and its latest attempt or ruling with the
evidence or reason. A finding stays `open` until its fix lands, a verifier
declines it with a reason, it needs a decision, or the user decides it.

The reviewer and fixer receive the criteria, context, and user decisions
verbatim, plus the findings list; the verifier receives them plus, for each
candidate, the entry it matches, if any. Settled findings and user decisions are
earlier conclusions, re-raised only when the current code shows their reason no
longer holds.

Match findings across rounds by mechanism, not wording or line. A finding
against the change a landed fix made re-raises that fix's finding.

## Loop

1. **Review.** Record the tip commit ID with
   `jj log -r <tip change ID> --no-graph -T commit_id`. Review the whole target
   on the first review, after step 4 reshapes the target, and when nothing
   landed since a `delta-pass`. Otherwise review the fix delta: pass
   `diff-review` a delta scope whose delta base is the tip commit ID recorded at
   the previous review, whose delta tip is the one just recorded, and whose
   changed revisions are those steps 6 and 7 recorded as changed since the last
   review, with their replaced-description marks. Then clear that record. Follow
   `diff-review` in this session as one that must stay independent of the
   target, so one fresh reviewer and one fresh verifier review and this session
   reviews no hunk itself. In either scope, pass the findings list as earlier
   findings, and add each `open` finding to the candidates under Verify: the
   verifier confirms it is still present or declines it with a reason. Per
   finding the review returns category, location, mechanism, and owning revision
   (the earliest target revision whose diff introduces the defect). A full
   review's `pass` ends the run unless a finding is `needs-decision`; then
   triage under step 2, ask under step 3, and end with `pass` unless the user
   stops the run or a decision made a finding `open` or calls for a reshape;
   such a decision continues with steps 4 to 8. `blocked` stops the run;
   `non-pass` continues to step 2. On `delta-pass`, triage under step 2, then
   continue from step 3 when any finding is `open` or `needs-decision`;
   otherwise start a full review.
2. **Triage.** A finding a user decision covers takes that decision's effect. A
   reasoned decline settles a finding unless the user asked for that change.
   `design` and `question` findings, findings owned outside the target, findings
   whose fix requires reordering, splitting, or moving changes between target
   revisions, re-raised `needs-decision` findings, and re-raises that meet the
   first Ask trigger are `needs-decision`. Everything else is `open`.
3. **Ask** the user when a trigger below holds, before fixing. Present the
   `needs-decision` findings with their history and any unsatisfied criteria,
   and offer: decide, continue, or stop. A decision calling for a change makes
   the finding `open`, unless it calls for reordering, splitting, or moving
   changes between target revisions, which step 4 handles; one to leave the code
   as is settles it. Triggers:
   - the review re-raises a `fixed` or `settled` finding, or an `open` one whose
     latest attempt is an evidenced rejection, and no user decision covers it;
   - the review returned `non-pass` and nothing is `open`;
   - a `delta-pass` left a finding `needs-decision`;
   - a full review's `pass` left a finding `needs-decision`;
   - 5 `non-pass` reviews, delta or full, since the last user checkpoint, unless
     a user decision set another limit.
4. **Reshape.** When a user decision calls for reordering, splitting, or moving
   changes between target revisions, follow `finalize-changes` before any fix
   this round, with the target as its explicit mutable history set and the
   decision as its boundary intent; it preserves the aggregate tree. Record the
   target's commit IDs first. If it stops and those commit IDs are unchanged,
   keep the finding `needs-decision` with its reason. If it stops after
   rewriting any of them, end the run as `blocked` and report the reshaped
   revisions, any conflicts, and the `finalize-changes` report, without further
   fixes. Otherwise re-resolve the target from its base to the reshaped tip,
   mark the finding `fixed`, and go to step 8; the next review is full because
   the reshape redraws every revision's diff.
5. **Fix.** Dispatch one fresh fixer for the round. For each owning revision
   with `open` findings, earliest first, run `jj new <owner>` and continue that
   fixer with the owner's change ID and findings; when the host cannot continue
   an agent, dispatch a fresh fixer per owner instead. The fixer follows
   `coding-style`, edits only the working copy, performs no VCS mutation or
   delegation, and returns per finding `fixed` with checks run, `rejected` with
   concrete evidence, or `needs-decision` with the question. The fixer never
   returns description text. When the owner's description became inaccurate, or
   a finding concerns the description, it returns facts instead: which
   statements no longer hold and what behavior was added, removed, or changed,
   citing the diff.
6. **Land.** Confirm the diff addresses each `fixed` finding, changes nothing
   else, and passes checks; otherwise abandon the working copy and keep those
   findings `open` as unverified. A rejection without evidence stays `open` as
   unverified; a rejection of a change the user asked for, or a `needs-decision`
   return, makes it `needs-decision` with the question. When the fixer returned
   description facts, this session rereads `finalize-changes`'
   `references/revision-descriptions.md` and composes the complete replacement
   from the owner's resulting diff, its current description, and the fixer's
   facts. The replacement must not mention reviews, findings, rounds, or fixes.
   Format and validate it with the options that reference gives. Then run
   `jj squash --from @ --into <owner>`, adding `--message "$desc"` for a
   replacement. A description-only finding squashes the empty working copy with
   the composed message. Mark the landed findings `fixed`, and record the owner
   as changed since the last review, marked when the squash replaced its
   description.
7. **Resolve conflicts** before the next fix. After each landing, list
   `jj log -r 'descendants(<owner>) & conflicts()' --reversed`. While a target
   revision is conflicted, run `jj new` on the earliest one and continue the
   round's fixer under the step 5 rules with its change ID, its description, and
   the landed findings, to keep the revision's intent and carry the fix. Land
   its resolution the same way, recording the revision as changed since the last
   review and marking a replaced description, and list again. Stop and ask the
   user when a resolution fails verification or needs a decision. Then stop when
   a descendant outside the target is newly conflicted.
8. After all fixes, run `jj new <target tip>` and return to step 1.

## Report

Lead with the outcome: `pass`, `blocked`, or `stopped by user`, with the last
`diff-review` report and its scope, full or delta, and the number of full and
delta reviews. Then list rewritten revisions, rebased descendants outside the
target, where `@` ends, findings by status, and checks run and skipped.

## Boundaries

- Never push, publish, or mutate external systems.
- Never rewrite references outside the target, except rebasing its descendants.
- Never lower the pass bar, edit criteria, or phrase requests to suppress
  findings.
