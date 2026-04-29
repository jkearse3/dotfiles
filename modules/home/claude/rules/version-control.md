# Version Control

## Commit Messages

Conventional Commits format by default. Defer to a repo's own conventions when documented
(CLAUDE.md, CONTRIBUTING.md, commitlint config). When undocumented, match existing style from recent
history.

### Subject

`type(scope): description`

- **type**: `feat`, `fix`, `refactor`, `style`, `chore`, `docs`, `test`, `ci`, `build`, `perf`
- **scope**: optional — module, component, or area affected
- **description**: imperative mood, lowercase, no period
- Keep the full subject under 72 characters
- Breaking changes: `type(scope)!: description`

### Body

Optional — add one for anything non-obvious. Separate from subject with a blank line. Wrap at 72
characters.

The subject and diff show _what_ changed at a surface level. The body adds context they can't
convey: the reasoning behind the change, and when needed, a higher-level description of _what_ was
done when the diff alone doesn't tell the full story.

### Atomicity

Prefer one logical change per commit. If the message needs "and", consider splitting — but use
judgment. Don't split when separation makes the individual commits harder to understand.

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

Always use `-m` to avoid interactive editor:

```bash
jj squash -m "message"                        # squash @ into @-
jj squash -r <rev> --into <target> -m "msg"   # explicit source/target
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
- `git-branch-checkout` - interactive branch checkout via fzf
- `git-branch-delete` - interactive branch deletion via fzf

### GitHub

Branch name is available directly via `git branch --show-current` or `$(git-branch-current)`.
