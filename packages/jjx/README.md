# jjx

`jjx` adds commands for [Jujutsu](https://jj-vcs.github.io/) workflows in these
dotfiles.

## Commands

| Command | Purpose |
| --- | --- |
| `bookmark` | Query, select, back up, push, rebase, and sweep bookmarks. |
| `change` | Interactively select a change. |
| `description` | Format a revision description. |
| `worktree` | Create or interactively select a Git worktree. |
| `ensure` | Initialize or validate jj state in an existing Git checkout. |

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
