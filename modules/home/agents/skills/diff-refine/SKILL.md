---
name: diff-refine
description: >-
  Proposes and applies behavior-preserving refinements to a finalized local jj
  revision, range, stack, or bookmark: simpler shape, reuse, naming, structure,
  type tightening, and evidenced performance. Use when the user asks to refine,
  simplify, polish, or optimize a finalized diff target in a jj repository. Not
  for bug fixing, review, working changes, Git-only checkouts, revision
  reshaping, or publication.
---

# Diff Refine

Find where a working target could take a better shape, let the user choose, and
apply the chosen refinements to the revisions that own them. One pass per
invocation; never loop.

## Target

Resolve the target as `diff-review` does, and require a jj repository and no
`<target> & immutable()` revisions. Refer to the target and every owning
revision by change ID, never commit ID, because each squash rewrites commits.

A caller, such as a skill that built the target, may pass context with the
target: constraints proposals must respect, such as acceptance criteria,
exclusions, and settled decisions; checks for each target revision, optionally
stated as already passing; and whether the caller reviews the target next.

Invoking this skill authorizes squashing chosen refinements into the target's
mutable revisions and rebasing their descendants. It authorizes nothing outside
the target and no publication.

## Proposal Rules

A proposal must:

- serve one lens: **simplicity** (reuse existing code, or drop concepts and
  anything else `coding-style`'s Keep the Change Minimal says the behavior does
  not need), **naming** (a name misleads, no longer matches the final behavior,
  breaks the domain vocabulary, or falls short of `coding-style`'s naming
  guidance), **structure** (placement, order, or coupling makes the code harder
  to find or change), **types** (tighten a type the target changes so it admits
  fewer states the code does not support, following `coding-style`'s Make
  Invalid States Unrepresentable, such as replacing a combination of nullable
  fields with a tagged union or moving checks repeated across consumers into one
  boundary parser), or **performance** (an evidenced algorithmic, I/O, or
  allocation cost on a reachable path);
- stay in scope: code the target changes, plus unchanged code the target made
  redundant or inconsistent. Read further only to settle a proposal, such as
  finding an existing helper or checking callers;
- fit in one owning revision: the earliest target revision that introduced the
  code, or for unchanged code, that made it redundant or inconsistent. It
  touches nothing a later target revision changes or depends on, so later
  revisions stay valid after the squash;
- state its concrete gain: what it removes, merges, clarifies, or makes cheaper;
- carry a decision flag, `needs-decision` when it depends on taste, product
  behavior, or a name the user owns. A `needs-decision` proposal also carries
  the question for the user and a recommended answer;
- preserve observable behavior, including contracts, output, errors, and
  persisted data. The one exception is renaming, or tightening the type of, a
  contract or durable name the target introduces, in the revision that
  introduced it, updating every use, including migrations, together. A contract
  or name that already exists in the target's base is a note for `diff-review`.
  Rate such a rename or tightening `medium` risk once it has left the local
  machine, such as through a pushed bookmark or a migration applied to a shared
  database;
- follow the repository's established patterns and `coding-style`, not the
  proposer's taste, and add no generality nobody needs.

Drop anything else. Report a refinement that spans target revisions as a note.
Zero proposals is a valid result. Report bugs, including a state the current
type admits that some path produces or some consumer mishandles, as notes for
`diff-review` or `diff-fix`, and mixed-concern revisions as notes for
`finalize-changes`; never fix or reshape them here.

## Flow

1. **Propose.** Dispatch a fresh read-only subagent with the target's change
   IDs, commits, base, any user focus, any caller constraints and per-revision
   checks, and **Proposal Rules**. It makes no edits, VCS mutation, or further
   delegation, and returns proposals ranked by gain, each with a `file:line`
   location, lens, owning revision, current and proposed shape, gain, risk
   (`low`, `medium`, `high`), and decision flag, with the question and
   recommended answer for a `needs-decision` one, plus its notes and
   proportionate checks for each target revision without caller checks. These
   are each revision's checks below. If the host cannot start a fresh agent,
   stop.
2. **Baseline.** Run the checks of each target revision, whether the caller or
   the proposer supplied them, in a fresh `jj new <rev>`, one revision at a
   time, skipping each revision whose checks the caller stated already pass.
   Then run `jj new <target tip>`. Mark each failing revision unchecked, and
   make each proposal that touches it `needs-decision` with that failure as its
   question. A proposal touches the revision it owns.
3. **Choose.** Present the proposals and let the user pick. Apply a standing
   choice without asking. It may select by risk, such as "all low-risk", or by
   the decision flag, such as "apply every proposal that needs no user decision;
   ask about the rest in one batch". A choice by the decision flag leaves each
   proposal's risk as rated, as information.
4. **Apply.** Apply the chosen proposals one at a time, by owning revision
   earliest first and in gain order within an owner. This session never edits
   files here; it only runs `jj new`, verification, squashes, restores, and
   reverts. For each proposal:
   1. Run `jj new <target tip>`, then record the current jj operation ID.
   2. Dispatch one fresh applier with the proposal and all caller context. If
      the host cannot start a fresh agent, stop. As in `diff-fix`'s fixer
      contract, the applier follows `coding-style`, edits only the working copy,
      and performs no VCS mutation or delegation. It knows no earlier proposal
      and rereads current code. Per revision it returns `applied` with checks
      run, `obsolete` when the code the proposal names is gone or already has
      the proposed shape, `failed` with evidence, including when the proposal's
      intent conflicts with landed code, or `needs-decision` with the question.
      It never returns description text; when a revision's description no longer
      holds, it returns facts instead: which statements no longer hold and what
      behavior changed, citing the diff.
   3. **Owner.** Run `jj new <owner>` and continue the applier with the owner's
      change ID, description, and checks. At an unchecked owner the applier
      makes the change and neither runs nor repairs that revision's checks.
      Verify the diff holds only the proposal's change, keeps the owner's
      described intent, and, unless the owner is unchecked, passes the owner's
      checks. When the applier returned description facts, reread
      `finalize-changes`' `references/revision-descriptions.md` and compose the
      complete replacement from the resulting diff, the current description, and
      those facts, never mentioning proposals, lenses, refinement, or review.
      Format and validate it with the options that reference gives. Run
      `jj squash --from @ --into <owner>` with `--message "$desc"` for a
      replacement, or `--use-destination-message` otherwise. Then list
      `jj log -r 'descendants(<owner>) & ~(<target>) & conflicts()'`; any result
      is a newly conflicted descendant outside the target.
   4. **Later revisions.** For every later target revision, earliest first, run
      `jj new <rev>` and continue the applier with its change ID, description,
      any conflict, and checks. The applier resolves conflicts and repairs check
      failures, keeping the revision's intent, then runs the revision's checks
      plus those of earlier checked target revisions whose files its diff
      touches. At an unchecked revision it only resolves conflicts and neither
      runs nor repairs that revision's checks. Verify the diff holds only
      conflict resolutions and repairs of failures this proposal caused, keeps
      the revision's described intent, and, unless the revision is unchecked,
      passes the checks the applier ran, then land it as at the owner. An empty
      working copy whose checks pass, or at an unchecked revision, needs no
      squash.
   5. **Retry.** On the first verification failure at a revision, run
      `jj restore` and continue the applier once with the failure. A second
      failure there fails the proposal.
   6. **Outcome.** An `obsolete` return at the owner ends the proposal
      `dropped (superseded)` without landing. A failed proposal, a
      `needs-decision` return, or a newly conflicted descendant outside the
      target triggers a revert; then mark the proposal `restored` with the
      reason and continue with the next. Otherwise it ends `applied`.

      To revert, inspect each operation after the recorded one with
      `jj op show`. If any was not made by this proposal's commands or the
      working-copy snapshots their checks triggered, such as through a `nix`
      wrapper, stop without reverting. Otherwise run `jj op revert` on each,
      newest first; never `jj op restore`. Then confirm nothing in the target is
      conflicted or divergent and `@` is an empty child of the target tip;
      otherwise stop.

5. **Check.** Run `jj new <target tip>`. Unless the run stopped or the caller
   stated that it reviews the target next, follow `diff-review` on the target in
   this session as one that must stay independent of the target, and report its
   verdict. Do not fix its findings; suggest `diff-fix` when it does not pass.

## Report

Lead with the outcome. It is `completed` when every proposal ends `applied`,
`declined`, `restored`, or `dropped`, and `stopped` only when a revert cannot
proceed or fails its post-check, or the host cannot start a fresh agent. Give
each proposal's status, with the reason for `restored` and `dropped`, and for a
stop the state left and the proposals not attempted. Then list unchecked
revisions, rewritten revisions and rebased descendants, checks run per revision
and their results, any `diff-review` verdict, and notes.
