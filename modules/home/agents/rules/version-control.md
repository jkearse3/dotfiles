# Version Control

## Repository Mode

Before any VCS operation, determine whether the workspace is in a Git repository using read-only
commands. In a Git repository, run `jj-ensure` before further VCS operations, even when the
requested work is otherwise read-only; this initialization is standing authorization. Then use jj
whenever it has an equivalent. Use Git only when an operation has no jj equivalent, its behavior
must occur specifically in Git, the user explicitly requests Git's view, or `jj-ensure` explicitly
reports an unsupported repository feature such as Git LFS. After any other `jj-ensure` failure, stop
before mutating work; read-only Git inspection may continue. Do not mix mutation models otherwise.
Never invoke `jj git init` directly or run `jj-ensure` outside a Git repository.

## Authority And Safety

When implementation is authorized, a plan identifying the change and base permits organizing
current-task, agent-authored, unpublished history. Ask before modifying anything published,
pre-existing and not task-owned, unrelated, user-authored, destructive, or of uncertain ownership.
Naming a target for inspection or review does not authorize modifying it. Use non-interactive VCS
commands.

## Reference Discovery

Use `jj-bookmark-{current,default,previous,stacked}` or the corresponding `git-branch-*` helpers to
discover bookmarks or branches. The jj `previous` and `stacked` helpers resolve relative to `@`;
only use them for another target after confirming `@` belongs to that target's stack.

In colocated repositories, Git may be detached. When `gh` requires a branch name, pass
`$(jj-bookmark-current)` explicitly.

## Publication

Do not push, publish references, create pull requests, merge, or close remote artifacts without an
explicit request. Before publication, inspect the outgoing revisions, target, review state, and
remote state.

Publish dependent stacks parent-first unless the hosting workflow provides an atomic stack
operation. Never force-push without explicit approval.
