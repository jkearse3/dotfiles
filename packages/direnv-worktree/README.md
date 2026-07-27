# direnv-worktree

Git globally registers `direnv-worktree post-checkout` for `post-checkout`, but
the hook does nothing unless the current repository has explicitly opted in.
From an authorized primary checkout with an evaluable `.envrc`, enroll the
repository with:

```console
$ direnv-worktree enable
```

On a subsequent `git worktree add`, the hook resolves the primary checkout from
`git worktree list --porcelain`, verifies that its environment is still
authorized and evaluable, and requires the new worktree's `.envrc` to be
byte-identical. It then authorizes and evaluates the new worktree before Git
returns. Both branch-backed and detached linked worktrees are supported. Clones,
primary worktrees, ordinary checkouts, and repositories without `.envrc` are
ignored.

Disable future automatic approvals without changing any existing direnv
approvals:

```console
$ direnv-worktree disable
```

Enrollment is the repository-local boolean `direnv.worktreeAutoAllow`, stored in
the common Git configuration shared by linked worktrees. Both enrollment
commands are idempotent.

If the hook rejects a worktree, `git worktree add` exits nonzero, but Git may
have already left the new worktree registered and present on disk. Inspect it
with `git worktree list`; after addressing the failure, either remove it with
`git worktree remove <path>` and retry or finish recovery in the existing
worktree. A failed target evaluation has its new direnv authorization revoked.
