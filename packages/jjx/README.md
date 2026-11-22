# jjx

`jjx` adds commands for [Jujutsu](https://jj-vcs.github.io/) workflows in these
dotfiles.

## Commands

| Command       | Purpose                                                      |
| ------------- | ------------------------------------------------------------ |
| `bookmark`    | Query, select, back up, push, rebase, and land bookmarks.    |
| `change`      | Interactively select a change.                               |
| `description` | Format a revision description.                               |
| `workspace`   | Create prepared jj workspaces and remove them.               |
| `worktree`    | Interactively select a Git worktree.                         |
| `ensure`      | Initialize or validate jj state in an existing Git checkout. |

Explore the command tree and preview description formatting:

```console
$ jjx --help
$ jjx bookmark land --help
$ jjx description format --dry-run
```

Home Manager configures `jj x` as an alias for `jjx`, so commands also work as
`jj x bookmark land`.

## Checkout setup

Use `jjx ensure` directly when a checkout does not yet have jj state:

```console
$ jjx ensure /path/to/checkout
```

The path defaults to the current directory. See [ensure.md](ensure.md) for
checkout setup, linked-worktree safety, and development instructions.

## Workspaces

`jjx workspace add` takes the same arguments as `jj workspace add` and then
prepares the new workspace the way Git's `post-checkout` hook prepares a new
worktree, because `jj workspace add` never runs that hook:

```console
$ jjx workspace add --name feature
```

Given `--name` without a destination, as above, it creates the workspace at
`~/.worktrees/<repository>/<name>`, creating missing parent folders, so every
workspace lives in one place whichever tool made it. `<repository>` is the
primary checkout's path relative to the home directory, such as `dotfiles` for
`~/dotfiles`; a primary checkout outside the home directory uses `_/` followed
by its absolute path without the leading `/`, such as
`~/.worktrees/_/srv/app/feature`. The location is the same when the command runs
in one of the repository's other workspaces. A given destination is used as is,
as `jj workspace add` uses it.

It runs `worktree-include` to copy the local files the primary checkout's
`.worktreeinclude` selects, then `direnv-worktree prepare` to authorize the
workspace's `.envrc` when the repository has enabled it. It prints the workspace
root on stdout. If a step fails, the workspace is kept and the error names the
commands to rerun.

`jjx workspace add` creates only colocated workspaces: it always passes
`--colocate` to `jj workspace add` and rejects `--no-colocate`. If the new
workspace still has no Git worktree of its own, it fails without preparing the
workspace, keeps it, and names the `jj workspace remove <name>` command that
removes it.

`jjx workspace remove [PATH]` removes the workspace containing `PATH` with
`jj workspace remove`, which snapshots its working copy into a commit and then
deletes its Git worktree and directory, including ignored files. It refuses
anything `jjx ensure` does not recognize as a workspace created by
`jj workspace add`, such as the primary checkout or a Git worktree with
independent jj state. `--dry-run` reports what would be removed.
