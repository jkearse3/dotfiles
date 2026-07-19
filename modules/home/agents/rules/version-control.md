# Version Control

## Repository Mode

Before VCS-affecting work, determine the repository mode using read-only commands. Use jj for
mutations in jj repositories and Git otherwise; do not mix mutation models. Ask before
`jj git init --colocate`. Never initialize jj for read-only work or outside a Git repository unless
explicitly requested.

## Authority And Safety

An implementation plan identifying the change and base authorizes shaping current-task,
agent-authored work into reviewable unpublished history: create, describe, split, or fold revisions
and move task-created references. Mutating a named existing target also requires clear ownership and
unpublished status; naming it for inspection or review grants no mutation authority.

Ask before affecting published, unrelated, or user-authored history; discarding changes; moving
pre-existing references; rewriting other descendants; or using an ambiguous base, target, or owner.
Destructive operations require an explicit request for the identified outcome. Avoid interactive
commands. Report mutations and requested work skipped or blocked.

## Placement And Atomicity

Before editing, inspect the working copy, parent, attached references, default reference, and
intended base. Start from the current position unless the user names another base. In jj, keep an
empty working copy's parent as the presumptive base; do not substitute an ancestral or default
bookmark. Continue non-empty work only for the same concern.

Keep one concern per revision. In jj, give each concern a task-owned, non-default bookmark. In Git,
reuse the current branch only when it is already task-specific; otherwise create a task branch. Use
the default reference only when explicitly requested. A task reference may inherit revisions outside
its concern from the current base, but its own revisions must remain focused.

## Finalization And Review

For unpublished agent-authored work:

1. Run focused verification and establish the fewest coherent, fully described revisions.
2. Finalize the implementation before review. In jj, create a fresh empty working-copy revision
   above the finalized work. In Git, commit the finalized work and leave a clean worktree.
3. Review each newly finalized or materially changed revision in dependency order. For one revision,
   that review also covers its aggregate delta from the intended base. For multiple revisions that
   jointly comprise the current task, also review `<parent>..<reference>` for integration issues. Do
   not re-review unchanged ancestors merely because they are present in the stack. If the parent or
   base is ambiguous, ask rather than guess.

Do not begin formal diff or revision review before the finalization conditions above hold.
Pre-finalization inspection by the implementor is verification, not review.

A final review covers the effective diff, description, boundaries, order, and base. Identify jj
revisions by stable change ID; commit IDs are evidence, not identity. Changes invalidate affected
reviews. A base change invalidates only reviews whose diffs or assumptions it changes. Re-review
descendants only when their diffs or assumptions change.

Create review fixes separately. Fold one into its target only when revision-local and the history is
unpublished and task-owned; then revalidate its description and repeat affected verification and
reviews from a clean working copy. Ask before involving multiple revisions, unrelated changes,
uncertain ownership, or other history. After changing a stack parent, restack descendants and repeat
affected verification and reviews. Move a task-created reference only after checks pass; ask before
moving a pre-existing reference.

## Revision Descriptions

Repository documentation, then recent history, determines subject format. Otherwise use
`type(scope): description`, with optional scope and `!` for breaking changes. Allowed types are
`feat`, `fix`, `refactor`, `perf`, `style`, `chore`, `docs`, `test`, `ci`, and `build`. Use an
imperative lowercase description without a period and keep it under 72 characters. Choose type by
effect: agent configuration is `feat` when behavior changes, `refactor` when reorganized, and `docs`
only when behavior is unchanged.

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

## Publication And Helpers

Do not push, publish references, create pull requests, merge, or close remote artifacts without an
explicit request. First inspect outgoing revisions, target, review state, and remote state. Publish
dependent stacks parent-first unless the hosting workflow provides an atomic stack operation. Never
force-push without explicit approval.

Use `jj-bookmark-{current,default,previous,stacked}` or corresponding `git-branch-*` helpers for
discovery. The jj previous and stacked helpers resolve relative to `@`; use them for another target
only after confirming `@` is on its stack. In colocated repositories, pass `$(jj-bookmark-current)`
when `gh` needs a branch name because Git may be detached.
