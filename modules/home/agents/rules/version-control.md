# Version Control

## Repository Mode

Before file-changing or VCS-affecting work, determine the repository mode with read-only commands:

- If jj is initialized, use jj for mutations and git only for read-only inspection.
- If a git repository lacks jj, ask before running `jj git init --colocate`.
- Do not initialize jj for read-only work.
- Do not initialize jj outside an existing git repository unless the user explicitly requests it.

Use the repository's active VCS for mutations. Do not mix mutation models in a colocated repository.

## Local Mutation Authority

Once an implementation request has produced a concrete gameplan identifying the intended change and
base, it authorizes the local VCS operations needed to turn current-task, agent-authored work into
reviewable unpublished history. This includes creating and describing commits or revisions,
splitting or folding current-task work, creating a fresh jj working-copy revision, and moving a
task-created local bookmark to the reviewed tip. A request that explicitly names an existing
revision or bookmark also authorizes those operations only when it asks for mutation and the
target's ownership and unpublished state are clear. Naming a target for inspection or review does
not authorize mutation.

That authority applies only within the stated gameplan. It does not cover published revisions,
unrelated or user-authored history, ambiguous bases or destinations, discarding changes, moving
pre-existing bookmarks, rewriting other descendants outside the current task or explicitly named
target stack, publication, pull requests, or remote named references. Inspect the affected state and
ask before crossing one of those boundaries. Avoid interactive VCS commands.

Do not run destructive commands such as `git reset --hard`, `git clean -fd`, or equivalent jj
operations unless the user explicitly requests the exact destructive outcome after the affected
state is identified.

## Work Placement

Before the first edit for a new logical change, inspect the working-copy state, current bookmark
when one exists, default bookmark, and intended base.

- Continue a non-empty working-copy revision only when the request belongs to that exact concern.
- Start a new concern from its intended base. If the current revision is unrelated, preserve it and
  use the intended base rather than creating a child that inherits unrelated ancestry.
- Ask when the intended base or dependency relationship cannot be inferred safely.
- A bookmark is optional for temporary local work but required for a contract, named branch,
  publication target, or stack element.

A revision must not contain unrelated changes, and a bookmark must not inherit revisions unrelated
to its concern.

## Reviewable Lifecycle

Treat clean revision history as part of implementation, not optional cleanup. Before a final review
of unpublished agent-authored implementation work can pass:

1. Run focused verification.
2. Establish the fewest coherent revision boundaries and validate complete descriptions for every
   resulting revision. In jj repositories, leave a fresh empty working-copy revision above the
   finalized work. In Git repositories, leave coherent, fully described commits and a clean
   worktree.
3. Review each revision in dependency order and the aggregate bookmark delta when the work spans
   multiple revisions.

An informal review of undescribed or unshaped working changes may guide implementation, but it is
not a final review pass. A final pass applies only to the exact reviewed content, descriptions,
revision boundaries, order, and base.

Keep review fixes isolated from reviewed content. Fold a fix into its target only when it addresses
that revision exclusively and the affected history is unpublished current-task work. Preserve or
revalidate the destination description, restore a clean working state above the reviewed tip, then
repeat affected verification and reviews. Ask when the destination or ownership is ambiguous, the
fix spans revisions, unrelated changes are present, or other history would be rewritten.

Bind a revision review to its stable change ID, effective diff, description, order, and base; record
the commit ID as evidence, not identity. Content changes, meaningful description changes, boundary
changes, or reordering invalidate the affected revision review. A changed base always invalidates
the aggregate review; re-review descendant revisions only when their effective diffs or assumptions
change.

## Stacked Bookmarks

Each bookmark is one review and publication unit and may contain one or more coherent revisions.
Base a dependent bookmark on its immediate parent bookmark; base independent work on the default or
other intended base rather than on the current stack tip.

For a linear stack, review every revision selected by `<parent>..<bookmark>` in dependency order,
then review that same aggregate delta for integration issues. Stop for an explicit base when a merge
or multiple plausible parent bookmarks make the range ambiguous. After a parent changes, restack its
descendants and repeat affected verification and reviews. Advance a task-created local bookmark to
the reviewed tip only after those checks pass; ask before moving a pre-existing bookmark.

## Revision Descriptions

Follow documented repository conventions, then recent history. Otherwise use Conventional Commits:

`type(scope): description`

- Allowed types are `feat`, `fix`, `refactor`, `perf`, `style`, `chore`, `docs`, `test`, `ci`, and
  `build`.
- Scope is optional and names the affected module, component, or area.
- Use an imperative, lowercase description without a trailing period.
- Keep the subject under 72 characters.
- Mark breaking changes with `!` before the colon.

Choose the type by behavioral effect rather than file format. Agent rules, skills, prompts, and
similar configuration are `feat` when they change behavior, `refactor` when they reorganize
behavior, and `docs` only when behavior is unchanged.

Keep one concern per revision.

Every revision description must include a non-empty body that explains why the change is needed; a
subject alone is never sufficient. The body must add information rather than restate the subject.
Describe the prior state or constraint first, then the change in response. Include relevant
constraints, durable behavior, compatibility boundaries, risks, excluded scope, and non-obvious
design choices. Do not include review history, tool output, scratch work, agent actions, task state,
workflow narration, or claims unsupported by the diff or durable project context.

Wrap body and footer lines at 72 characters, except for unbreakable URLs and inline code. Separate
footers from the body with a blank line. Use `Closes #123` or `Fixes JIRA-456` for issue references.
Breaking-change footers start with `BREAKING CHANGE:`.

## Message Validation

Before writing any agent-authored git commit message or jj revision description, assign the complete
message to a shell variable and validate that exact value:

```bash
printf '%s\n' "$desc" | commit-message-check
```

Pass `"$desc"` unchanged to the mutating command. If validation fails, revise the message and rerun
the checker. If the user supplied an exact invalid message, stop and report the validation failure.

## Publication

Do not push, publish bookmarks or branches, create pull requests, merge, or close remote artifacts
unless explicitly requested. Before publication, inspect the outgoing revisions, target, review
state, and remote state. Publish dependent stacks parent-first unless the hosting workflow provides
an atomic stack operation. Never force-push without explicit approval.

In a colocated jj repository, pass `$(jj-bookmark-current)` when a `gh` command requires a branch
name because git may be detached.

## Available Helpers

Use `jj-bookmark-{current,default,previous,stacked}` or the corresponding `git-branch-*` helpers for
repository and stack discovery. The jj previous and stacked helpers resolve relative to `@`; use
them for another target only after confirming `@` is on that target's stack.

Report VCS mutations performed, including created or moved revisions and named references, and any
requested mutation that was skipped or blocked.
