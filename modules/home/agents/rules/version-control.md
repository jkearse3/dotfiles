# Version Control

## Repository Mode

Before other VCS operations, run
`if test "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true; then jjx ensure; fi`.
Its documented local setup and repair have standing authorization, including for
read-only work. Never invoke `jj git init` directly.

After `jjx ensure` succeeds, use jj for repository mutation and do not mix
mutation models. Use Git mutation only when jj is unavailable or unsupported, or
Git is explicitly required. After any other `jjx ensure` failure, allow only
read-only Git inspection.

## History And References

Implementation authorization includes locally finalizing verified,
agent-authored task changes without further confirmation; it does not authorize
publication. Use `finalize-changes` for finalization and history shaping.
Rewriting published, unrelated, user-authored, or uncertain-ownership history
requires explicit authorization.

Finalized revisions must be useful bisect points and safe to land on main
individually: if history stops at any revision, the codebase must be safe to
deploy and use as is. Each revision must contain one coherent concern and must
not knowingly rely on a descendant revision to build, pass its applicable
checks, preserve required behavior, or be safe to use. Prefer ordering over new
mechanisms: land internals before the change that exposes them, add a
replacement safeguard before removing the original, keep interfaces usable by
consumers the revision cannot update, and keep persisted state the parent
revision produced usable or migrate it within the revision. A breaking change to
interfaces or persisted state is exempt from those two requirements only when
the user requested or approved it and the revision description declares it. When
compatibility costs more than it is worth, propose the break with that cost
before implementing it. Keep supporting tests, documentation, configuration,
migrations, and revision-local fixes in the earliest revision whose concern
requires them. Repair a known-failing revision; retaining one requires explicit
user approval.

Before new work, establish a task-owned Git branch or jj bookmark for that
change set. In jj, inspect `@` directly; bookmark an empty `@`, or create and
bookmark an empty child. Stack on current work unless the user specifies another
base. Reuse a reference only for the same change set and keep it at the
change-set tip. Treat reference-helper output as discovery; verify exact
attachment and stack ownership before mutation.

## Shared jj Workspaces

A checkout whose `.jj/repo` is a file is a jj workspace that shares its
repository, operation log, and bookmarks with the repository's other workspaces,
each with its own `@`. Treat another workspace's working-copy commit, shown as
`<name>@`, and its ancestors outside trunk and your task-owned stack as owned by
that workspace; rewriting, abandoning, or moving bookmarks on them requires
explicit authorization. So do repository-wide operation commands such as
`jj op restore` and any `--allow-cross-workspace` override. Target abandon,
rebase, and bookmark commands by change IDs and bookmark names your task
created, never by a revset rooted at trunk. When jj refuses because another
workspace's commit is immutable, narrow the target; `--ignore-immutable`
requires explicit authorization. To reverse a cross-workspace mistake, use
`jj op revert <operation>`, not `jj undo`. When jj reports a stale working copy,
run `jj workspace update-stale` only if the rewritten revisions belong to your
task-owned stack; otherwise stop and report it.

## Remote Bookmarks

When the task continues an existing remote branch by adding revisions to it, run
`jj bookmark track <name> --remote <remote>` and use the resulting local
bookmark as the task bookmark. When the task only reads the branch, for review,
inspection, or as the base of a different change set, use `<name>@<remote>` as a
revision and leave it untracked. Quote names with special characters as
`"<name>"` in `jj bookmark track` and `jj bookmark list` arguments and as
`"<name>"@<remote>` in revisions. Always pass `--remote`, because leaving it out
tracks every remote with that bookmark name. Never fake tracking with
`jj bookmark create` or `jj bookmark set` on `<name>@<remote>`, which makes an
untracked copy that fetches never update, and never continue the branch under a
new bookmark name. Tracking someone else's branch does not authorize pushing to
it; Publication still governs every push.

Before tracking, run `jj bookmark list --all <name>`. If it shows
`<name>@<remote>` already tracked, do not track again; use the local `<name>` as
the task bookmark, subject to History And References and Shared jj Workspaces.
If an untracked local `<name>` points somewhere other than `<name>@<remote>`,
tracking merges the two, which can move it to the remote commit or leave it
conflicted, so stop and report it unless the local bookmark is task-owned and
the reconciliation is clear. After tracking, confirm with the same listing that
`<name>` is tracked and not conflicted: jj exits 0 when it merely warns about a
missing or already-tracked bookmark and when tracking leaves a conflict. Do not
track a new bookmark before its first push, because `jj git push --bookmark`
tracks the remote bookmark it creates.

## Publication

Publish references, push, create or merge pull requests, or close remote
artifacts only when explicitly requested and after inspecting the exact outgoing
changes, destination, and relevant remote state. Publish dependent stacks
parent-first unless the hosting workflow is atomic. Force-pushing requires
explicit approval.
