# jjx

`jjx` adds commands for [Jujutsu](https://jj-vcs.github.io/) workflows in these
dotfiles.

## Commands

| Command       | Purpose                                                      |
| ------------- | ------------------------------------------------------------ |
| `bookmark`    | Query, select, back up, push, rebase, and sweep bookmarks.   |
| `change`      | Interactively select a change.                               |
| `description` | Format a revision description.                               |
| `workspace`   | Create prepared jj workspaces and remove them.               |
| `worktree`    | Create or interactively select a Git worktree.               |
| `ensure`      | Initialize or validate jj state in an existing Git checkout. |

Explore the command tree and preview description formatting:

```console
$ jjx --help
$ jjx bookmark sweep --help
$ jjx description format --dry-run
```

Home Manager configures `jj x` as an alias for `jjx`, so commands also work as
`jj x bookmark sweep`.

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
$ jjx workspace add ../feature --name feature
```

It runs `worktree-include --prepare` to copy the local files the primary
checkout's `.worktreeinclude` selects, then `direnv-worktree prepare` to
authorize the workspace's `.envrc` when the repository has enabled it. It prints
the workspace root on stdout. If a step fails, the workspace is kept and the
error names the commands to rerun. A workspace created with `--no-colocate` has
no Git worktree and is not prepared.

`jjx workspace remove [PATH]` removes the workspace containing `PATH` with
`jj workspace remove`, which snapshots its working copy into a commit and then
deletes its Git worktree and directory, including ignored files. It refuses
anything `jjx ensure` does not recognize as a workspace created by
`jj workspace add`, such as the primary checkout or a `jjx worktree add`
worktree. `--dry-run` reports what would be removed.

`jjx worktree add` still creates worktrees with independent jj state.
