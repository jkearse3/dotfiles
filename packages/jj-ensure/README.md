# jj-ensure

`jj-ensure` makes an existing Git checkout usable with
[jj](https://jj-vcs.github.io/) by validating or creating a matching jj
workspace, then keeping jj's commit identity in agreement with Git's. It is
idempotent and deliberately conservative: a compatible workspace passes through
untouched, an incompatible one produces an error instead of being replaced, and
the only automatic repair is a narrowly authenticated fix for one relocation
scenario.

```console
$ jj-ensure [PATH] [--dry-run]
```

`PATH` defaults to the current directory and may be anywhere inside the
checkout. On success the command prints the canonical Git worktree root; on
failure it prints one concise `error:` line to stderr and exits nonzero.
`--dry-run` runs all discovery and pre-mutation safety checks, then describes
the single action execution would take without modifying anything.

## What it does

Each run selects exactly one action:

- **Nothing** — the checkout already has a compatible jj workspace.
- **Initialize a primary checkout** — no `.jj` exists, so the repository is
  initialized with `jj git init --colocate`.
- **Initialize a linked worktree** — no `.jj` exists in a `git worktree add`
  checkout, so jj is initialized with `--git-repo` pointing at the worktree's
  private Git directory (see below).
- **Enroll a legacy linked workspace** — a compatible linked workspace that
  predates the identity marker gains one; its jj state is not reinitialized.
- **Repair a relocated linked workspace** — see
  [Relocation repair](#relocation-repair).

After any of these, Git's resolved commit identity for the checkout is mirrored
into jj's repository-local configuration. After a **fresh initialization only**,
the default branch's remote-tracking bookmark is also tracked — see
[Tracking the default remote bookmark](#tracking-the-default-remote-bookmark).

## Linked worktrees

Git gives every linked worktree a private Git directory under the primary
repository's `.git/worktrees/<name>`. jj can use that private directory as its
Git backend, which gives each linked worktree an independent jj workspace (its
own working copy, operation log, and bookmarks) while all worktrees keep sharing
the primary repository's object database.

This is an **unsupported jj compatibility mechanism**, not a documented jj
feature, so `jj-ensure` refuses to treat path names as proof of identity.
Discovery requires the checkout to appear exactly once in `git worktree list`,
and for linked worktrees the private Git directory reached through the checkout
must be the same filesystem object as the one reached through that registration.
Retest `jj-ensure` after jj upgrades.

### The identity marker

When a linked workspace is initialized (or a compatible legacy one is enrolled),
`jj-ensure` writes a marker file, `jj-ensure-target`, into the worktree's
private Git directory. It records the authenticated attachment target — the
private Git directory itself, as raw filesystem bytes. The marker is created
exclusively (an existing marker is never overwritten) and advances only after a
successful relocation repair. Its purpose is to let a later run prove that a
stale jj target belongs to this workspace rather than to some unrelated
repository.

## Relocation repair

Moving the primary repository breaks a linked workspace: jj's
`.jj/repo/store/git_target` file still holds the old absolute path to the
private Git directory. Recovery order matters:

1. Run `git worktree repair` so Git itself can identify the linked worktree's
   new private directory.
2. Run `jj-ensure` in the linked worktree.

`jj-ensure` rewrites `git_target` only when every check agrees: the workspace is
a linked worktree, the stale target no longer exists on disk, it exactly matches
the recorded identity marker, both old and new paths end in the same
`worktrees/<name>` pair sitting under a directory named `.git`, and the new path
sits under Git's currently discovered common directory. A target that still
exists points somewhere real but incompatible — that is not evidence of
relocation and is never rewritten.

The write is atomic (staged in the same directory, then `os.replace`d). After
rewriting, the repaired repository is re-validated against both jj and a fresh
Git discovery; only then does the identity marker advance. If validation fails,
the stale target is restored, and a rollback failure is reported alongside the
original error. Repair never touches Git's own registration, never recreates an
existing jj repository, and never modifies working-copy files — the operation
history survives.

## Commit identity mirroring

Git resolves the correct per-worktree identity through `includeIf gitdir:`
conditions, which key off the private Git directory. jj's config scoping keys
off the workspace checkout path instead, so a worktree checked out under an
unrelated directory would fall back to jj's default identity. To keep the two in
agreement wherever the checkout lives, `jj-ensure` reads Git's resolved
`user.name`, `user.email`, and SSH signing selection and writes them into the
workspace's `--repo` jj config:

- With `commit.gpgSign=true`, `gpg.format=ssh`, and a configured
  `user.signingKey`, jj gets `signing.backend = "ssh"`, the selected
  `signing.key`, and `git.sign-on-push = true`.
- Otherwise jj gets `signing.backend = "none"` and `git.sign-on-push = false`;
  non-SSH signing shapes are deliberately not guessed at.

If Git resolves no complete identity, nothing is mirrored. For a freshly
initialized workspace whose empty working-copy commit still carries jj's default
author, the author is realigned once via `jj metaedit --update-author`; a
pre-existing workspace's commits are never rewritten.

## Tracking the default remote bookmark

`jj git init` imports remote-tracking bookmarks but does not track them, so
after initializing over a checkout with a remote, the default branch shows up as
an untracked `name@origin` and pulls would not update a local bookmark until you
ran `jj bookmark track` by hand. After a **fresh initialization only**,
`jj-ensure` runs that command for you.

The default branch is taken from the remote `HEAD` that Git records locally in
`refs/remotes/<remote>/HEAD` — the same signal jj's own `trunk()` detection
uses, set by `git clone` and `git remote set-head`, read without any network
access. When exactly one remote has a recorded HEAD it is used; when several do,
`origin` wins. Anything else — no recorded remote HEAD, or a multi-remote tie
without an `origin` — tracks nothing rather than guessing.

Tracking is a convenience, never a gate. It runs only on fresh initialization,
so a bookmark you later `jj bookmark untrack` is not re-tracked on the next run.
A missing or ambiguous default is a silent no-op, and a detection or
`jj bookmark track` failure is reported as a `warning:` on stderr while the
ensure still succeeds — the validated workspace stays usable and you can track
manually.

## Safety properties

- Checkouts configured for Git LFS (via any active `.gitattributes`,
  `info/attributes`, configured, XDG, or system attribute file) are rejected
  before anything is touched, because jj does not support LFS.
- A pre-existing `.jj` that is not a plain directory, or a workspace whose jj
  root or Git backend does not match the checkout, fails validation instead of
  being replaced.
- A failed initialization removes only the `.jj` state that invocation created;
  a failed marker write removes only the marker so a later run can retry.
- Read-only jj queries run with `--ignore-working-copy`, so inspection never
  snapshots the working copy or creates jj operations.

## Package layout

- `src/jj_ensure/cli.py` — the whole implementation; the module docstring is the
  authoritative behavioral summary.
- `tests/test_jj_ensure.py` — behavior and safety tests against real `git` and
  `jj` binaries in temporary repositories.
- `tests/completion_test.py` — shell-completion checks.
- `jj-ensure.fish`, `_jj-ensure` — fish and zsh completions, installed by the
  package.
- `package.nix` — Nix build (`buildPythonApplication`); wraps the binary so
  `git` and `jj` are on `PATH`, and runs the test suites plus a `--help` smoke
  test as install checks.

## Development

Run the tests directly (the behavior suite needs `git` and `jj` on `PATH`, the
completion suite `fish` and `zsh`; `PYTHONPATH=src` makes the tests import the
working tree instead of an installed `jj_ensure` package):

```console
$ PYTHONPATH=src python3 -B -m unittest discover -s tests -p 'test_*.py'
$ PYTHONPATH=src python3 -B -m unittest discover -s tests -p 'completion_test.py'
```

Or build the package, which runs them as install checks:

```console
$ nix build .#jj-ensure
```
