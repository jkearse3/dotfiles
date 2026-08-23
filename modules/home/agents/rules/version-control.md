# Version Control

## Repository Mode

Before any VCS operation, use `git rev-parse --is-inside-work-tree` to determine
whether the workspace is a Git repository. If so, run `jj-ensure`; this
initialization has standing authorization, including for read-only requests.
Never run it outside a Git repository or invoke `jj git init` directly.

After successful initialization, prefer jj and do not mix mutation models. Use
Git only when jj lacks the operation, Git is specifically required, the user
requests Git's view, or `jj-ensure` reports an unsupported feature such as Git
LFS. After any other `jj-ensure` failure, allow only read-only Git inspection.

## History And References

Implementation authorization plus a plan naming the change authorizes organizing
its agent-authored, unpublished history. Finalizing that verified, task-owned
work into described commits is part of completing the task, not a separate
opt-in: once the changes are verified, finalize them without pausing to ask
whether to commit. This authority is local only and never implies publication,
which the Publication section still gates. Ask before modifying published,
unrelated, user-authored, pre-existing non-task-owned, destructive, or
uncertain-ownership history. Use non-interactive VCS commands.

Perform commit and revision shaping (creating, splitting, squashing, reordering,
and rewording) through the finalize-changes skill rather than ad hoc VCS
mutation, so boundaries and descriptions follow one governed path. Treat a
revision as unfinalized until its description passes `commit-message validate`;
format it with `commit-message format` or `jj-description-format` and treat a
nonzero exit as blocking. Never hand-write a description that skips this gate.

Before mutating content or history, identify the change set with the current
task-owned Git branch or a task-owned jj bookmark; a reference identifying only
its base or another change set does not qualify. Default new work to the
checked-out revision or branch tip. Assume stacking on current work is
intentional; a differently named reference alone creates no ambiguity.

For new work, create a Git branch at the base or bookmark an empty jj
working-copy revision there. Inspect `@` itself before using bookmark helpers:
bookmark an empty `@` directly; otherwise create and bookmark an empty child.
Reuse a reference only for the same change set and keep it at the change-set
tip. After jj finalization, leave the bookmark on the finalized tip and any
empty working-copy child unbookmarked. This authority covers creating and moving
the reference, not publishing it. Before completion, verify it points to the
finalized tip.

Discover references with `jj-bookmark-{current,default,previous,stacked}` or the
corresponding `git-branch-*` helpers. `jj-bookmark-current` finds the nearest
contextual bookmark, which may not be attached to `@`; when exact attachment
affects placement, ownership, or history mutation, inspect `@` with
`jj log -r @ --no-graph -T 'local_bookmarks'`. Before using `previous` or
`stacked` for another target, confirm `@` belongs to that target's stack.

In colocated repositories, Git may be detached. When `gh` requires a branch
name, pass `$(jj-bookmark-current)` explicitly.

## Publication

Publish references, push, create pull requests, merge, or close remote artifacts
only when explicitly requested and after inspecting outgoing revisions, target,
review state, and remote state. Publish dependent stacks parent-first unless the
hosting workflow supports an atomic operation. Force-pushing requires explicit
approval.
