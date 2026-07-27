---
name: finalize-changes
description: >-
  Manages Git commits or jj revisions for verified repository changes or
  authorized mutable history, including creating, splitting, squashing,
  reordering, rewording, and leaving a clean state. Use when working changes are
  verified and ready to commit or when existing unpublished history needs
  shaping. Not for producing or repairing repository content, verification,
  review, publication, or releases.
argument-hint: "[verified working changes | explicit mutable history set]"
---

# Finalize Changes

Convert verified repository changes or explicitly authorized mutable history
into the fewest coherent, fully described commits or revisions needed for
review, rollback, and a cohesive history. Preserve the aggregate tree and leave
a clean post-finalization state.

## Input

```text
$ARGUMENTS
```

Infer and confirm:

- **Target**: verified working changes, or an explicit mutable history set. Do
  not infer a history rewrite boundary from unrelated ancestry.
- **Boundary intent**: default to the fewest coherent revisions. Treat "single
  revision", "describe only", and "do not split" as single-revision intent.
- **Authority**: finalization must be explicitly requested or covered by current
  implementation authority. Verification claims authorize no broader history
  rewrite.

Stop when working changes lack verification, changes are still being
implemented, the target is empty, or its base, ownership, publication state, or
rewrite boundary is ambiguous. Never rewrite published, unrelated,
user-authored, pre-existing, or uncertain history without explicit authority.

## Runbook

1. Inspect repository mode, working state, target ancestry, bookmarks or
   branches, publication state, and full existing descriptions. Resolve the
   immutable base and the complete target tree before mutation.
2. Analyze the effective diff, changed files, dependencies, and existing
   boundaries. Keep code, tests, documentation, configuration, and migrations
   together when they support one concern.
3. Propose the fewest coherent commits or revisions in dependency order. Split
   independent concerns; combine partial steps and revision-local fixes. If a
   requested single target is incoherent, stop and ask to narrow it or permit
   multiple revisions.
4. Only when creating or rewriting descriptions, read
   `references/revision-descriptions.md`, then compose and validate each
   complete description. The diff controls what changed; supplied context may
   explain why but must not invent unsupported content or expose workflow
   internals.
5. Select and read exactly one procedure for the repository mode:
   - `procedures/jj.md` for a jj repository.
   - `procedures/git.md` for a Git repository without jj support.
6. Execute non-interactively, verify the resulting aggregate tree matches the
   original target tree, and stop on conflicts or unexpected changes.
7. Leave finalized work inactive. For a jj target ending at the pre-finalization
   `@`, create a fresh empty child above the final tip; for another jj target,
   preserve the required empty active position. Leave the Git worktree and index
   clean.
8. Report the immutable base, ordered change and commit IDs, full descriptions,
   transformations, moved task-owned references, tree-preservation result,
   conflicts, and final clean state.

## Boundaries

- Finalization does not implement, repair, verify, formally review, publish,
  push, merge, release, or mutate external systems.
- Use only non-interactive VCS commands. Never open an editor or interactive
  patch selector.
- Preserve unrelated working changes by stopping rather than absorbing,
  resetting, stashing, or discarding them.
- Move only a clearly task-owned bookmark or branch when needed to identify the
  finalized tip.
