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

## Publication

Publish references, push, create or merge pull requests, or close remote
artifacts only when explicitly requested and after inspecting the exact outgoing
changes, destination, and relevant remote state. Publish dependent stacks
parent-first unless the hosting workflow is atomic. Force-pushing requires
explicit approval.
