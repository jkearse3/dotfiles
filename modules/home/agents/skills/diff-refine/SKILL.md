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
   IDs, commits, base, any user focus, and **Proposal Rules**. It makes no
   edits, VCS mutation, or further delegation, and returns proposals ranked by
   gain, each with a `file:line` location, lens, owning revision, current and
   proposed shape, gain, risk (`low`, `medium`, `high`), and decision flag, with
   the question and recommended answer for a `needs-decision` one, plus its
   notes. If the host cannot start a fresh agent, stop and report.
2. **Choose.** Present the proposals and let the user pick. Apply a standing
   choice without asking. It may select by risk, such as "all low-risk", or by
   the decision flag, such as "apply every proposal that needs no user decision;
   ask about the rest in one batch". A choice by the decision flag leaves each
   proposal's risk as rated, as information.
3. **Apply.** For each owning revision with chosen proposals, earliest first:
   1. Record the current jj operation ID, then create a fresh empty child of the
      owner.
   2. Make only the chosen changes following `coding-style`, confirm the diff
      holds only those changes, and run proportionate checks.
   3. When the owner's description became inaccurate, reread `finalize-changes`'
      `references/revision-descriptions.md` and compose the complete replacement
      from the owner's resulting diff and its current description, using the
      chosen proposals only as facts about what changed. Never copy proposal
      text, and never mention proposals, lenses, refinement, or review. Format
      and validate it with the options that reference gives.
   4. Run `jj squash --from <child> --into <owner>` with `--message "$desc"` for
      a replacement, or `--use-destination-message` otherwise.
   5. Run `jj new <target tip>`, then proportionate checks there.

   When checks fail or any rewritten revision is conflicted, stop applying. If
   `jj op log` shows only this step's operations after the recorded one, run
   `jj op restore <recorded operation ID>`, which keeps earlier owners'
   refinements; otherwise leave the state as is and report it.

4. **Check.** Run `jj new <target tip>`. Unless Apply stopped, follow
   `diff-review` on the target in this session as one that must stay independent
   of the target, and report its verdict. Do not fix its findings; suggest
   `diff-fix` when it does not pass.

## Report

Lead with the outcome, `completed` or `stopped`, and the number of proposals
applied, declined, and dropped. For a stop, name the owners that landed, the
failure, and the restored operation or the unrestored state. Then list the
rewritten revisions and rebased descendants, checks run and their results, any
`diff-review` verdict, and notes.
