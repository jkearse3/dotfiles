# Version Control

## Placement

Before creating new work, confirm its placement.

- If on trunk, ask for a bookmark name.
- If on an existing bookmark, ask whether to stack on the current bookmark or start from another
  base.
- When starting from an empty `@`, create the bookmark on the existing empty `@` revision; do not
  run `jj new` first. `jj new` creates an additional empty child revision, so edits would sit on top
  of an unnecessary empty parent.

This does not apply to maintenance of existing work, such as reordering, describing, splitting,
squashing, or rebasing named revisions, but those mutations still require explicit approval.

## Commit Messages

Default to Conventional Commits unless repo conventions say otherwise. Check documented conventions
first, then recent history.

### Subject

Use `type(scope): description`.

- Allowed types: `feat`, `fix`, `refactor`, `perf`, `style`, `chore`, `docs`, `test`, `ci`,
  `build`.
- Scope is optional and should name the affected module, component, or area.
- Description is imperative, lowercase, has no period, and keeps the full subject under 72 chars.
- Breaking changes use `type(scope)!: description`.

Type follows behavioral effect, not file format. Agent rules, skills, prompts, and other markdown
configs are `feat` when they change behavior, `refactor` when they restructure behavior, and `docs`
only when they do not affect behavior.

### Body

Agent-authored messages include a body by default. Use a subject-only message only when the subject
fully explains the change.

The body explains why the change exists: prior state, intent, durable behavior, risk, or non-obvious
design choices. Do not describe review history, tool output, scratch work, or session workflow.

Wrap body text at 72 columns. Keep unbreakable tokens intact.

### Footer

Optional, except when introducing breaking changes. Separate from body with a blank line.

- Issue references: `Closes #123`, `Fixes JIRA-456`.
- Breaking changes start with `BREAKING CHANGE:`.

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

Using jj collocated with git. Always in detached HEAD state; use git for read-only ops only.

### Setup Pre-Flight

Before file-changing or VCS-affecting work, detect repository state with read-only commands: check
for initialized jj first, then check whether the directory is a git repository without jj. Prefer jj
for file-changing or VCS-affecting work in git repositories.

When a git work repository lacks jj initialization, the approved plan must explicitly include
`jj git init --colocate` before edits or VCS-mutating commands proceed. Treat the plan approval as
approval to run that initialization command. After initialization, verify bookmark and
default-branch state before edits or VCS-mutating commands proceed; apply the VCS placement rules
below using jj bookmarks.

Reference-only clones, research, questions, and explanations do not trigger jj initialization unless
the user asks to modify the repository or run VCS-mutating commands. Directories without git are not
initialized with jj unless the user explicitly asks to initialize a new repository.

### Terminology

- Revision description: the message content stored on a jj revision, composed from the subject,
  expected body, and optional footer.
- Commit: the lifecycle action that finalizes `@` with `jj commit` and creates a fresh working-copy
  revision.
- Describe: the lifecycle action that updates an existing revision description with `jj describe`.

### Revision Descriptions

Compose the full revision description before passing it to jj: subject, expected body, and optional
footer. Do not reduce a change to a subject-only description just because the command uses `-m`.

### Commands

- `jj commit -m "<revision-description>"` - finalize @ with a revision description and create fresh
  working copy. **Not** `jj new -m` (puts a description on a new empty revision, not the one with
  changes).
- `jj new` - create empty working copy on current
- `jj new -m "$desc"` - create new revision with a message; assign `desc` and validate it with
  `printf '%s\n' "$desc" | commit-message-check` first (use to start new work)
- `jj describe <revision> -m "<revision-description>"` - set revision description
- `jj diff -r <revision> --git` - diff revision (use `--stat` for file list)
- `jj log -r <rev> --no-graph -T 'change_id' --limit 1` - verify revision exists / get change ID
- `jj log -r '<first>::<last>' --no-pager` - show commit range
- `jj-bookmark-default` - trunk/default branch name
- `jj-bookmark-current` - current branch name
- `jj-bookmark-previous` - previous branch name (stacked PRs, else trunk)
- `jj-bookmark-stacked` - list bookmarks from current to trunk
- `jj log -r "$(jj-bookmark-previous)..@" --stat` - files changed in current branch
- `jj log -r '<from>..<to>' --stat` - files changed in custom range

### GitHub

For `gh` commands, use `$(jj-bookmark-current)` to get branch name since always detached.

### Patterns

#### Splitting

Use `jj split` with filesets only when whole files belong in an earlier revision. Selected changes
become a new parent; remaining changes stay in the target revision.

For multiple splits, use the `Remaining changes: <change_id>` output as the next target. Describe the
final remaining revision only after all splits are complete.

Agents must not run interactive `jj split -i`. When changes in one file need hunk-level splitting,
keep the affected hunks together and tell the user they can split them manually.

#### Squashing

Prefer `jj squash -m "$desc"` to avoid an interactive editor. Capture and validate the destination
revision's full description first because `-m` replaces the entire description, not just the subject.

## Git

Use git primarily for read-only inspection unless jj is unavailable.

Useful commands:

- `git-branch-current` - current branch name
- `git-branch-default` - default remote branch name
- `git-branch-stacked` - branches in stack from current to default
- `git-branch-previous` - previous branch in stack
- `git-branch-next` - next branch in stack (child)

For `gh`, use `git branch --show-current` or `$(git-branch-current)`.
