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

## Placement And Atomicity

Before editing, inspect the working copy, parent, current and default bookmark or branch, and
intended base. Start from the current position; if the user specifies another base, move there
before editing. Otherwise, use an empty jj working copy's parent rather than another bookmark.
Continue existing changes only when they belong to the same concern.

Keep concerns separate in revisions and delegation. Give each concern a task-owned, non-default
bookmark or branch, creating one unless the current bookmark or branch is already task-specific.
Advance that reference after checks pass. Ask before moving any other reference or one whose
ownership or purpose is uncertain. Use the default bookmark or branch only when explicitly
requested.

Assign a mutating delegate at most one concern, including its base, ownership boundary, and focused
validation. The caller remains responsible for finalizing and reviewing that concern before
delegating another independent concern.

## Finalization And Review

Complete each independently reviewable concern in unpublished, agent-authored work before starting
another:

1. Run focused verification and organize the concern into the fewest coherent, fully described
   revisions.
2. Finalize it before formal review: create an empty jj working-copy revision above it, or commit it
   in Git and leave the worktree clean.
3. Review every new or materially changed revision in dependency order, then review the concern's
   aggregate delta from its intended base. Ask if the base is ambiguous.

Resolve applicable findings before starting another concern. After all concerns are complete, run
deferred integration checks and review the complete task range for cross-concern issues.

A review covers the effective diff, description, revision boundaries, order, and base. Refer to jj
revisions by stable change ID. Repeat only reviews affected by changed diffs or assumptions,
including base or parent changes.

Create review fixes separately. Fold a fix into its target only when it is revision-local and the
history is unpublished and task-owned. After folding or changing a parent, revalidate descriptions,
restack affected descendants, and repeat affected verification and review from a clean working copy.
Ask before modifying multiple revisions or any unrelated, pre-existing and not task-owned,
user-authored, published, or uncertain history.

## Revision Descriptions

Repository documentation determines the revision description format. When the repository does not
specify one, use Conventional Commits: `type(scope): description`, with an optional scope and `!`
for breaking changes.

Default types are `feat`, `fix`, `refactor`, `perf`, `style`, `chore`, `docs`, `test`, `ci`, and
`build`. Use an imperative lowercase description without a period, and keep the complete subject
under 72 characters. Choose the type by effect: agent configuration is `feat` when behavior changes,
`refactor` when reorganized, and `docs` only when behavior is unchanged.

Every agent-authored description requires a non-redundant body explaining why. Describe the prior
state or constraint, then the response. Include material constraints, durable behavior,
compatibility, risks, exclusions, and non-obvious choices. Exclude review history, tool output,
scratch work, agent actions, task state, workflow narration, and unsupported claims.

Wrap body and footer lines at 72 characters except unbreakable URLs and inline code. Separate
footers with a blank line; use `Closes #123`, `Fixes JIRA-456`, and `BREAKING CHANGE:` as
applicable.

Format each complete agent-authored message into `desc`, validate that exact value, and pass it
unchanged to the mutation:

```bash
desc="$(printf '%s\n' "$desc" | commit-message-format)"
printf '%s\n' "$desc" | commit-message-check
```

If validation fails, revise and repeat. Never format an exact user-supplied message; if it fails
validation, stop and report the failure.

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
