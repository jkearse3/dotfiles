# Version Control

## Commit Messages

Conventional Commits format by default. Defer to a repo's own conventions when documented
(CLAUDE.md, AGENTS.md, CONTRIBUTING.md, commitlint config). When undocumented, match existing style
from recent history.

### Subject

`type(scope): description`

- **type**: one of
  - `feat`: new feature
  - `fix`: bug fix
  - `refactor`: code change that neither adds a feature nor fixes a bug
  - `perf`: a `refactor` specifically targeting performance
  - `style`: formatting, whitespace, non-semantic changes
  - `chore`: repo housekeeping that does not ship (gitignore, editor configs, internal tooling
    configs)
  - `docs`: documentation only
  - `test`: adding or correcting tests
  - `ci`: CI/CD pipelines, deploy scripts, IaC, monitoring, recovery procedures
  - `build`: build system or external dependencies, including lockfile and manifest updates
- **scope**: optional: module, component, or area affected. Do not use issue identifiers as scopes.
- **description**: imperative mood, lowercase, no period. Think "This commit will `<description>`".
- Keep the full subject under 72 characters
- Breaking changes: `type(scope)!: description`

Type follows behavioral effect, not file format. A markdown file the system reads as config (agent
rules, skills, prompts) takes `feat` when it changes behavior, `refactor` when it restructures, and
`docs` only when the change doesn't affect what the system does.

### Body

Optional — add for anything non-obvious; separate from subject with a blank line. Wrap at 72
columns; unbreakable-token handling follows `markdown.md` § Width (cap 72; quoted output — errors,
logs, command lines — counts as unbreakable). Prefer rephrasing over overrun: long URL → footer
trailer (`Link: <url>`), or reference a short ticket ID.

The subject and diff show _what_; the body adds the _why_, plus a higher-level _what_ when the diff
isn't self-explanatory. Open with the status quo or bug, then the change in response.

Explain the change on its own terms, in domain language — describe intent and domain context, not
the workflow that produced it (its stages, task IDs, or tooling). Don't lean on session-internal
artifacts — planning notes, scratch files, transcripts, workflow-tool docs — even when tracked;
readers shouldn't chase pointers. Exception: commits whose primary change is the artifact itself.

Contextual mood: imperative for the change ("Replace the polling loop"), past for the prior state
("The cache leaked under concurrent writes"), present for invariants ("The buffer is a fixed-size
ring").

### Footer

Optional, except when introducing breaking changes. Separate from body with a blank line.

- Issue references: `Closes #123`, `Fixes JIRA-456`.
- Breaking changes start with `BREAKING CHANGE:` followed by a description.

### Special Cases

Exempt from Conventional Commits, use git defaults: initial commit `chore: init`; merge
`Merge branch '<branch>'`; revert `Revert "<subject>"`.

### Atomicity

Prefer one logical change per commit. If the message needs "and", consider splitting — but use
judgment. Don't split when separation makes the individual commits harder to understand.

### Example

Exhaustive — scope, breaking `!`, why-first body with contextual mood, and both footers:

```
feat(auth)!: require signed tokens on all endpoints

Unsigned tokens were accepted on internal routes, leaving a forgery gap.
All endpoints now verify the signature and reject unsigned tokens.

BREAKING CHANGE: Unsigned tokens are rejected. Clients must upgrade to
the v2 SDK before deploying.

Closes #482
```

## Jujutsu (jj)

Using jj collocated with git. Always in detached HEAD state; use git for read-only ops only.

### Commands

- `jj commit -m "<message>"` - finalize @ with message and create fresh working copy. **Not**
  `jj new -m` (puts message on new empty revision, not the one with changes).
- `jj new` - create empty working copy on current
- `jj new -m "<message>"` - create new revision with message (use to start new work)
- `jj describe <revision> -m "<message>"` - set revision message
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

#### Splitting Revisions

##### By File

`jj split` with filesets - select which files go into first commit:

```bash
jj split -r <rev> -m "first commit msg" path/to/file1 path/to/file2
# Selected files → new parent, remaining stays in <rev>

jj describe -r <rev> -m "final commit msg"
# Describe whatever remains
```

##### Multi-commit Splitting

When splitting into N commits, track the target revision through each split:

```bash
jj split -r <target> -m "first commit" file1 file2
# "Remaining changes: <new_target> ..." — use <new_target> for next split

jj split -r <new_target> -m "second commit" file3

jj describe -r <final_target> -m "last commit"
jj log -r '<first>::<last>' --no-pager
```

Parse `jj split` output:

- `Selected changes : <change_id>` — the new commit created
- `Remaining changes: <change_id>` — update target for next split

##### Limitations

Hunk-level splits (splitting changes within a single file) require interactive mode (`jj split -i`),
which is not available. When a file needs hunk-level splitting:

- Merge the affected groups into one commit
- Note the limitation to user
- User can run `jj split -i` manually if needed

#### Squashing Revisions

Prefer `-m` to avoid interactive editor, but **capture the destination's full description first** —
`-m` replaces the entire description, not just the subject:

```bash
desc=$(jj log -r <dest> --no-graph -T 'description')
jj squash -r <rev> -m "$desc"
```

#### Anti-patterns

- `jj new -r @-` + `jj restore --from <source>` - convoluted, loses context
- Creating empty revisions then populating - unnecessary steps
- Using `jj describe` before all splits complete - describe only the final remaining revision
- `jj squash` without `-m` when revisions have descriptions — triggers interactive editor

## Git

### Commands

- `git-branch-current` - current branch name
- `git-branch-default` - default remote branch name
- `git-branch-stacked` - list branches in stack from current to default
- `git-branch-previous` - previous branch in stack
- `git-branch-next` - next branch in stack (child)

### GitHub

Branch name is available directly via `git branch --show-current` or `$(git-branch-current)`.
