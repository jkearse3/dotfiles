# jjx

`jjx` collects the dotfiles Jujutsu workflow extensions behind one discoverable
Python command tree.

```console
$ jjx --help
$ jjx bookmark sweep --help
$ jjx description format --dry-run
$ jjx ensure /path/to/checkout
```

Commands are grouped under `bookmark`, `change`, `description`, and `worktree`;
checkout initialization remains the top-level `ensure` command.

Home Manager also configures `jj x` as an alias for `jjx`, so the same tree is
available as `jj x bookmark sweep`. Use `jjx ensure` directly when preparing a
checkout that does not yet contain jj state. See [ensure.md](ensure.md) for the
checkout and linked-worktree safety model used by `jjx ensure`.
