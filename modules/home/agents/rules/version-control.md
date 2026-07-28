# Version Control

## Repository Mode

Before any VCS operation, use read-only commands to determine whether the
workspace is a Git repository. If it is, run `jj-ensure` before further VCS
operations; this initialization is standing authorization, including for
read-only requests. Never run `jj-ensure` outside a Git repository or invoke
`jj git init` directly.

After successful initialization, prefer jj. Use Git only when no jj equivalent
exists, the operation specifically requires Git, the user requests Git's view,
or `jj-ensure` reports an unsupported feature such as Git LFS. After any other
`jj-ensure` failure, do not mutate work; read-only Git inspection may continue.
Do not otherwise mix mutation models.

## History And References

Implementation authorization and a plan naming the change permit organizing
current-task, agent-authored, unpublished history. Ask before modifying history
that is published, unrelated, user-authored, pre-existing and not task-owned,
destructive, or of uncertain ownership. Use non-interactive VCS commands.

Before mutating content or history, identify the intended change set with a
task-owned local reference: the current Git branch or a jj bookmark. For new
work, an existing reference that identifies only the base or another change set
does not satisfy this invariant. Unless the user specifies another base, use the
current checked-out revision or branch tip as the base for new work. Treat
stacking on the current work as intentional by default; a differently named
current reference does not by itself make the base or stacking unclear.

For new work, create a Git branch at the intended base or bookmark an empty jj
working-copy revision there. Determine placement from `@` itself before using
bookmark helpers: if `@` is empty, bookmark it directly and do not create
another revision; only when `@` is not empty, create and bookmark an empty
child. Reuse a reference only for the same change set. Keep the reference at the
change-set tip. After jj finalization, leave the bookmark on the finalized tip
and any empty working-copy child unbookmarked. Implementation authority covers
creating and moving the reference, not publishing it. Before completion, verify
the task-owned reference points to the finalized tip.

Discover references with `jj-bookmark-{current,default,previous,stacked}` or the
corresponding `git-branch-*` helpers. `jj-bookmark-current` reports the nearest
contextual bookmark, not necessarily a bookmark attached to `@`; when exact
attachment affects placement, ownership, or history mutation, inspect `@`
directly with `jj log -r @ --no-graph -T 'local_bookmarks'`. Because the jj
`previous` and `stacked` helpers resolve relative to `@`, confirm that `@`
belongs to another target's stack before using them for that target.

In colocated repositories, Git may be detached. When `gh` requires a branch
name, pass `$(jj-bookmark-current)` explicitly.

## Publication

Only publish references, push, create pull requests, merge, or close remote
artifacts when explicitly requested. First inspect the outgoing revisions,
target, review state, and remote state.

Publish dependent stacks parent-first unless the hosting workflow supports an
atomic stack operation. Force-pushing requires explicit approval.
