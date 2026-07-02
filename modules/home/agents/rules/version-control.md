# Version Control

## Placement

Before creating new work, confirm its placement.

- If on trunk, ask for a bookmark name.
- If on an existing non-default bookmark, ask where to place the new work with first-class choices:
  create a new bookmark stacked on the current bookmark, continue on the current bookmark, or start
  from another base. Prefer the new stacked bookmark option unless the user's request clearly
  continues the current work.
- When starting from an empty `@`, create the bookmark on the existing empty `@` revision. Do not
  run `jj new` first, because it creates an unnecessary empty parent.

This does not apply to maintenance of existing work, such as reordering, describing, splitting,
squashing, or rebasing named revisions, but those mutations still require explicit approval.

## Commit Messages

Default to Conventional Commits unless repo conventions say otherwise. Check documented conventions
first, then recent history.

### Subject

Use `type(scope): description`.

- Allowed types: `feat`, `fix`, `refactor`, `perf`, `style`, `chore`, `docs`, `test`, `ci`, `build`.
- Scope is optional and should name the affected module, component, or area.
- Description is imperative, lowercase, has no period, and keeps the full subject under 72 chars.
- Breaking changes use `type(scope)!: description`.

Type follows behavioral effect, not file format. Agent rules, skills, prompts, and other markdown
configs are `feat` when they change behavior, `refactor` when they restructure behavior, and `docs`
only when they do not affect behavior.

### Body And Footer

Agent-authored messages include a body by default. Use a subject-only message only when the subject
fully explains the change.

The body explains why the change exists: prior state, intent, durable behavior, risk, or non-obvious
design choices. Do not describe review history, tool output, scratch work, or session workflow.

Wrap body text at 72 columns. Keep unbreakable tokens intact.

Footers are optional, except when introducing breaking changes. Separate them from the body with a
blank line. Use `Closes #123` or `Fixes JIRA-456` for issue references, and start breaking-change
footers with `BREAKING CHANGE:`.

### Atomicity

Prefer one logical change per commit. If the message needs "and", consider splitting, but do not
split when that makes the individual commits harder to understand.

### Message Validation

Before an agent runs any git or jj command that writes a commit message or revision description with
`-m`, assign the message to a shell variable and validate the exact variable that will be passed to
the command:

```bash
printf '%s\n' "$desc" | commit-message-check
```

Use the same variable unchanged after validation. This applies to every agent-run git or jj message
write, including commit, amend, describe, split, squash, and `jj new -m`.

If validation fails, revise and rerun the checker. If the user supplied an exact invalid message,
stop and report the validation failure instead of writing it.

## Jujutsu (jj)

Use jj colocated with git for file-changing and VCS-affecting work. These repositories are usually
in detached HEAD, so use git for read-only inspection only unless jj is unavailable.

### Setup Pre-Flight

Before file-changing or VCS-affecting work, detect repository state with read-only commands: check
for initialized jj first, then check whether the directory is a git repository without jj.

When a git work repository lacks jj initialization, the approved plan must explicitly include
`jj git init --colocate` before edits or VCS-mutating commands proceed. Treat the plan approval as
approval to run that initialization command.

After initialization, verify bookmark and default-branch state before edits or VCS-mutating commands
proceed. Apply the placement rules above using jj bookmarks.

Reference-only clones, research, questions, and explanations do not trigger jj initialization unless
the user asks to modify the repository or run VCS-mutating commands. Directories without git are not
initialized with jj unless the user explicitly asks to initialize a new repository.

### Commands

Compose the full revision description before passing it to jj: subject, expected body, and optional
footer. Do not reduce a change to a subject-only description just because the command uses `-m`.

- `jj commit -m "$desc"` - finalize `@` and create a fresh working copy. Do not use `jj new -m` for
  existing changes; it describes a new empty revision.
- `jj new` - create an empty working copy on the current revision.
- `jj new -m "$desc"` - start new work with a described empty revision.
- `jj describe -r <rev> -m "$desc"` - replace a revision description.
- `jj diff -r <rev> --git` - show a revision diff; add `--stat` for file lists.
- `jj log -r '<first>::<last>' --no-pager` - show a revision range.
- `jj-bookmark-default` - default bookmark.
- `jj-bookmark-current` - current bookmark.
- `jj-bookmark-previous` - previous bookmark in the stack, or trunk.
- `jj-bookmark-stacked` - bookmarks from current to trunk.
- `jj log -r "$(jj-bookmark-previous)..@" --stat` - files changed in current branch.

For `gh` commands, use `$(jj-bookmark-current)` as the branch name because git is detached.

### Splitting And Squashing

Use `jj split` with filesets only when whole files belong in an earlier revision. Selected changes
become a new parent; remaining changes stay in the target revision.

For multiple splits, use the `Remaining changes: <change_id>` output as the next target. Describe
the final remaining revision only after all splits are complete.

Agents must not run interactive `jj split -i`. When changes in one file need hunk-level splitting,
keep the affected hunks together and tell the user they can split them manually.

Prefer `jj squash -m "$desc"` to avoid an interactive editor. Capture and validate the destination
revision's full description first because `-m` replaces the entire description, not just the
subject.

## Git

Use git primarily for read-only inspection unless jj is unavailable.

Useful commands:

- `git-branch-current` - current branch name
- `git-branch-default` - default remote branch name
- `git-branch-stacked` - branches in stack from current to default
- `git-branch-previous` - previous branch in stack
- `git-branch-next` - next branch in stack (child)

For `gh`, use `git branch --show-current` or `$(git-branch-current)`.
