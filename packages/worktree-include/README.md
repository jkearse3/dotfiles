# worktree-include

`worktree-include` copies local, gitignored files such as `.env` or
`.claude/settings.local.json` from one worktree of a repository into another, so
a new Git worktree or colocated jj workspace starts with them.

```console
$ worktree-include [--source PATH] [--dry-run] [DESTINATION]
```

`DESTINATION` defaults to the current directory's worktree and `--source` to the
repository's primary worktree. Both must be distinct worktrees of the same
repository.

## Selecting files

The source worktree's `.worktreeinclude` lists patterns in `.gitignore` syntax.
A file is copied only when it matches one of those patterns **and** the source
worktree's own ignore rules ignore it, so tracked and merely untracked files are
never copied. Paths under `.jj/` are never selected: jj ignores its own
metadata, but that metadata belongs to each workspace. This is the convention
Claude Code's `--worktree` and Conductor also read.

Gitignore semantics apply, including two common surprises:

- A pattern without a slash matches at any depth: `.dev.vars` also selects
  `.devenv/.dev.vars`. Anchor it as `/.dev.vars` to mean only the root file.
- A file cannot be re-included or excluded with `!` once its parent directory is
  matched. Write `local/**` with `!local/skip.json`, not `local/`.

Without a `.worktreeinclude`, the command reports that there is nothing to copy
and succeeds. Whether the file is committed or kept local is up to each
repository.

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

Nothing runs this automatically: neither Git nor jj copies ignored files when
creating a worktree or workspace, so call it after creation.

## Development

```console
$ python3 -B -m unittest discover -s packages/worktree-include/tests -p 'test_*.py'
$ nix build .#worktree-include
```
