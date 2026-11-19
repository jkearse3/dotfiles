---
name: finalize-changes
description: >-
  Manages Git commits or jj revisions for verified repository changes or
  authorized mutable history, including creating, splitting, squashing,
  reordering, rewording, and leaving a clean state. Use when working changes are
  verified and ready to commit or when existing history in the task's stack
  needs shaping. Not for producing or repairing repository content,
  verification, review, publication, or releases.
---

# Finalize Changes

Convert verified repository changes or authorized mutable history into the
fewest coherent, fully described, independently valid revisions, preserving the
aggregate tree.

## Input

- **Target**: verified working changes, or an explicit mutable history set
  within the task's stack under the version-control rules. Do not infer a
  rewrite boundary from unrelated ancestry.
- **Boundary intent**: default to the fewest coherent revisions. Treat "single
  revision", "describe only", and "do not split" as single-revision intent.

Stop when working changes lack verification, changes are still being
implemented, the target is empty, or its base, ownership, or rewrite boundary is
ambiguous.

## Runbook

1. Resolve the immutable base and the complete target tree before mutation.
   Existing boundaries and order are evidence, not constraints.
2. Propose the fewest revisions that satisfy Sequencing. If a requested single
   target is incoherent, stop and ask to narrow it or permit multiple revisions.
   If no split, order, or combination makes every revision independently valid,
   stop without mutation and report the failing requirement; never add or change
   content to satisfy it. A breaking change the user requested or approved
   counts as valid when its description declares it.
3. Only when creating or rewriting descriptions, reread
   `references/revision-descriptions.md` immediately before composing each
   description, even when it was read earlier in the session and always after
   context compaction or summarization; a remembered or summarized version never
   substitutes for the file. Compose from the diff; supplied context, such as a
   summary of the work, may explain why but is evidence, never text to copy.
   Declare a breaking change the user requested or approved with `!` and a
   `BREAKING CHANGE:` footer, rewriting an existing description that lacks them.
4. Read and follow exactly one procedure for the repository mode:
   - `procedures/jj.md` for a jj repository.
   - `procedures/git.md` for a Git repository without jj support.
5. Report the immutable base, ordered change and commit IDs, full descriptions,
   transformations, rebased descendants, moved task-owned references, known
   per-revision verification status and gaps, the tree-preservation result,
   conflicts, and the final clean state.

## Sequencing

These rules specialize the version-control rules on coherent, independently
valid revisions. Whoever applies them sets the granularity, meaning how finely
to split or whether to squash into existing revisions; these rules decide
boundaries and order within it.

- A revision is coherent when one description explains it as one reviewable
  concern without unrelated clauses.
- Give each behavior change that a user, caller, or other system would notice
  its own revision when it can land without the others, so it can be reviewed,
  reverted, and bisected alone.
- Put a behavior-preserving refactor that makes room for a change in its own
  revision, immediately before the first revision that relies on it unless
  another revision must come between them.
- Keep mechanical changes such as renames, moves, formatting, and dependency
  bumps apart from logic changes.
- Never split supporting tests, documentation, configuration, migrations, or
  revision-local fixes into revisions of their own.
- Order dependencies first. Otherwise put simpler changes before more complex
  ones, with fewer files as the final tie-breaker.
- Do not split merely because files differ by type or layer.

## Boundaries

- Use only non-interactive VCS commands. Never open an editor or interactive
  patch selector.
- Preserve unrelated working changes by stopping rather than absorbing,
  resetting, stashing, or discarding them.
- Move only the task-owned bookmark or branch, and verify it identifies the
  finalized tip.
