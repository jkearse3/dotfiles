---
name: diff-refine
description: >-
  Proposes and applies behavior-preserving refinements to a finalized local jj
  revision, range, stack, or bookmark: simpler shape, reuse, naming, structure,
  and evidenced performance. Use when the user asks to refine, simplify, polish,
  or optimize a finalized diff target in a jj repository. Not for bug fixing,
  review, working changes, Git-only checkouts, revision reshaping, or
  publication.
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

- serve one lens: **simplicity** (drop concepts, indirection, branches,
  parameters, or state the behavior does not need, or reuse existing code),
  **naming** (a name misleads or breaks the domain vocabulary), **structure**
  (placement, order, or coupling makes the code harder to find or change), or
  **performance** (an evidenced algorithmic, I/O, or allocation cost on a
  reachable path);
- stay in scope: code the target changes, plus unchanged code the target made
  redundant or inconsistent. Read further only to settle a proposal, such as
  finding an existing helper or checking callers;
- fit in one owning revision: the earliest target revision that introduced the
  code, or for unchanged code, that made it redundant or inconsistent. It
  touches nothing a later target revision changes or depends on, so later
  revisions stay valid after the squash;
- state its concrete gain: what it removes, merges, clarifies, or makes cheaper;
- preserve observable behavior, including contracts, output, errors, and
  persisted data;
- follow the repository's established patterns and `coding-style`, not the
  proposer's taste, and add no generality nobody needs.

Drop anything else. Report a refinement that spans target revisions as a note.
Zero proposals is a valid result. Report bugs as notes for `diff-review` or
`diff-fix` and mixed-concern revisions as notes for `finalize-changes`; never
fix or reshape them here.

## Flow

1. **Propose.** Dispatch a fresh read-only subagent with the target's change
   IDs, commits, base, any user focus, and **Proposal Rules**. It makes no
   edits, VCS mutation, or further delegation, and returns proposals ranked by
   gain, each with a `file:line` location, lens, owning revision, current and
   proposed shape, gain, and risk (`low`, `medium`, `high`), plus its notes. If
   the host cannot start a fresh agent, stop and report.
2. **Choose.** Present the proposals and let the user pick. Apply a standing
   choice such as "all low-risk" without asking.
3. **Apply.** For each owning revision with chosen proposals, earliest first:
   1. Record the current jj operation ID, then create a fresh empty child of the
      owner.
   2. Make only the chosen changes following `coding-style`, confirm the diff
      holds only those changes, and run proportionate checks.
   3. When the owner's description became inaccurate, compose and validate a
      replacement as `finalize-changes` describes.
   4. Run `jj squash --from <child> --into <owner>` with `--message "$desc"` for
      a replacement, or `--use-destination-message` otherwise.
   5. Run `jj new <target tip>`, then proportionate checks there.

   When checks fail or any rewritten revision is conflicted, stop applying. If
   `jj op log` shows only this step's operations after the recorded one, run
   `jj op restore <recorded operation ID>`, which keeps earlier owners'
   refinements; otherwise leave the state as is and report it.

4. **Check.** Run `jj new <target tip>`. Unless Apply stopped, dispatch one
   fresh `diff-review` of the target and report its verdict. Do not fix its
   findings; suggest `diff-fix` when it does not pass.

## Report

Lead with the outcome, `completed` or `stopped`, and the number of proposals
applied, declined, and dropped. For a stop, name the owners that landed, the
failure, and the restored operation or the unrestored state. Then list the
rewritten revisions and rebased descendants, checks run and their results, any
`diff-review` verdict, and notes.
