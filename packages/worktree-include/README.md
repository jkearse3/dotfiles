# worktree-include

`worktree-include` copies local, gitignored files such as `.env` or
`.claude/settings.local.json` from a repository's primary worktree into a linked
one, so a new Git worktree or colocated jj workspace starts with them.

```console
$ worktree-include [--dry-run] [DESTINATION]
```

`DESTINATION` defaults to the current directory's worktree. In a primary
checkout, a repository whose primary worktree is bare, or a repository without a
`.worktreeinclude`, the command does nothing and prints nothing.

## Selecting files

The primary worktree's `.worktreeinclude` lists patterns in `.gitignore` syntax.
A file is copied only when it matches one of those patterns **and** the primary
worktree's own ignore rules ignore it, so tracked and merely untracked files are
never copied. Paths under `.jj/` are never selected: jj ignores its own
metadata, but that metadata belongs to each workspace. This is the convention
Claude Code's `--worktree` and Conductor also read.

Gitignore semantics apply, including two common surprises:

- A pattern without a slash matches at any depth: `.dev.vars` also selects
  `.devenv/.dev.vars`. Anchor it as `/.dev.vars` to mean only the root file.
- A file cannot be re-included or excluded with `!` once its parent directory is
  matched. Write `local/**` with `!local/skip.json`, not `local/`.

Whether `.worktreeinclude` is committed or kept local is up to each repository.

## Copy behavior

- Each copied path is printed as `copied PATH`; `--dry-run` prints
  `would copy PATH` and writes nothing.
- Existing destination paths are never replaced. An identical file is reported
  as `unchanged`; a differing one is kept and reported on stderr. Rerunning is
  therefore safe.
- File modes and timestamps are preserved, and symlinks are copied as symlinks.
- Copies never write through a destination directory that resolves outside the
  destination worktree, and a destination path whose parent is blocked by a file
  or dangling symlink fails before anything is written for it.

## Running automatically on `git worktree add`

Home Manager registers `worktree-include --post-checkout` as a global Git
`post-checkout` hook, so every `git worktree add`, including one run by another
tool, populates the new worktree from the primary one. The hook acts only on a
branch checkout from the null commit into a linked worktree; clones, ordinary
checkouts, bare repositories, and repositories without a `.worktreeinclude` are
left alone silently. A copy failure makes `git worktree add` exit nonzero after
Git has already created the worktree; fix the cause and rerun `worktree-include`
inside it.

The hook runs before `direnv-worktree`, so a new worktree's `.envrc` can rely on
the copied files.

Tools that create linked worktrees without running Git's hooks can run
`worktree-include DESTINATION` afterwards. `jj workspace add` never runs this
hook, so create jj workspaces with `jjx workspace add`, which does.

## Development

```console
$ python3 -B -m unittest discover -s packages/worktree-include/tests -p 'test_*.py'
$ nix build .#worktree-include
```
