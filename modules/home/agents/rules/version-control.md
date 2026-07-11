# Version Control

## Repository Mode

Before file-changing or VCS-affecting work, determine the repository mode with read-only commands:

- If jj is initialized, use jj for mutations and git only for read-only inspection.
- If a git repository lacks jj, ask before running `jj git init --colocate`.
- Do not initialize jj for read-only work.
- Do not initialize jj outside an existing git repository unless the user explicitly requests it.

After initialization, determine the current and default bookmarks before placing new work.

## Work Placement

Apply this gate only when starting a new logical change:

- If the current bookmark is missing or default, ask for a bookmark name.
- If the requested work continues the current non-default bookmark, continue there.
- If the work is separate or its relationship is unclear, ask whether to create a bookmark stacked
  on the current bookmark, continue on the current bookmark, or use another base. Prefer a stacked
  bookmark.
- When placing work on an empty `@`, create the bookmark on `@`; do not run `jj new` first.
- When stacking from a non-empty `@`, run `jj new` before creating the bookmark.

This gate does not apply to maintenance of existing work, such as describing, reordering, splitting,
squashing, or rebasing named revisions. Those mutations still require explicit approval.

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

Prefer one logical change per revision. Split only when separate revisions would materially improve
review, rollback, or understanding, and each resulting revision remains coherent on its own. Do not
split changes that are clearer or only valid together.

Include a body when the subject alone does not explain the reason, constraints, durable behavior,
compatibility boundary, risk, excluded scope, or non-obvious design choice. Describe the prior state
or constraint first, then the change in response. Do not include review history, tool output,
scratch work, agent actions, task state, workflow narration, or claims unsupported by the diff or
durable project context.

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

Compose the complete description before invoking jj. Do not reduce it to a subject-only description
because the command accepts `-m`.

## Jujutsu Safety

Use `jj commit -m "$desc"` to finalize existing changes and create a fresh working copy. Do not use
`jj new -m` for existing changes; it describes a new empty revision.

Do not use interactive VCS commands. Use filesets for non-interactive `jj split`. If changes in one
file require hunk-level splitting, keep them together and tell the user they can split them
manually.

Before using `jj squash -m`, capture and validate the complete destination description because `-m`
replaces it rather than appending to it.

## Available Helpers

These custom commands are available for repository inspection and stack navigation:

- `jj-bookmark-current` finds the nearest unambiguous descendant or ancestor bookmark.
- `jj-bookmark-default` returns the default bookmark.
- `jj-bookmark-previous` returns the previous bookmark in the stack, or the default bookmark.
- `jj-bookmark-stacked` lists bookmarks from the current bookmark to the default bookmark.
- `git-branch-current` returns the current branch.
- `git-branch-default` returns the default remote branch.
- `git-branch-previous` returns the previous branch in the stack.
- `git-branch-next` returns the next child branch in the stack.
- `git-branch-stacked` lists branches from the current branch to the default branch.

In a colocated jj repository, pass `$(jj-bookmark-current)` when a `gh` command requires a branch
name because git may be detached.
