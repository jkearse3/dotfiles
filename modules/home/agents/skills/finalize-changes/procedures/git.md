# Finalize With Git

Use this procedure only in a Git repository where jj is unavailable or explicitly unsupported. The
target is verified working changes or an explicit unpublished, task-owned commit set authorized for
rewrite.

## Inspect And Record

1. Inspect the worktree, index, current branch, upstream, base, target commits, full messages, and
   publication state. Require a clearly task-owned non-default branch for new work. Stop for a
   detached HEAD, unrelated changes, an uncertain base or branch, or commits that may be published.
   Mutable-history finalization additionally requires a clean current worktree and index before any
   rewrite; staged-boundary handling applies only to working-change finalization.
2. Record the immutable base and target tree. For working changes, the base is `HEAD`. Inspect
   staged and unstaged path sets separately and stop if a path occurs in both; divergent index and
   worktree content is ambiguous finalization input. Build the target tree without changing the real
   index by recording its tree, loading that tree into a temporary index, and layering only intended
   unstaged and untracked paths from the worktree onto it:

   ```bash
   staged_tree="$(git write-tree)"
   temporary_index="$(mktemp)"
   rm "$temporary_index"
   GIT_INDEX_FILE="$temporary_index" git read-tree "$staged_tree"
   GIT_INDEX_FILE="$temporary_index" git add -A -- <unstaged-and-untracked-intended-paths>
   target_tree="$(GIT_INDEX_FILE="$temporary_index" git write-tree)"
   rm "$temporary_index"
   ```

   An empty worktree path set needs no temporary-index `git add`. Stop if any staged path is outside
   the intended target or either intended path set is ambiguous. For mutable history, require an
   explicit contiguous range whose tip is the guarded current task-branch tip, then record that
   tip's tree ID. Include every descendant through the branch tip rather than dropping or implicitly
   authorizing it.

3. Inventory every changed path and assign each hunk to a coherent proposed commit. If independent
   commits require interactive hunk selection and no safe path-level boundary exists, stop or
   combine them rather than guessing.
4. Inspect the real index separately. Stop if it contains a path outside the intended target. If the
   result needs multiple commits, require an initially empty index; do not reinterpret or
   redistribute an existing staged boundary.

## Create Or Rewrite Commits

- Prefer path-scoped, non-interactive staging such as `git add -- <paths>`. Never use `git add -p`,
  `git commit --interactive`, or an editor.
- Before each commit, inspect the staged diff and confirm both its path set and content exactly
  match one proposed coherent concern. Stop if any other staged entry remains. Keep supporting
  tests, documentation, configuration, and migrations with that concern.
- Before creating or rewriting a description, read `references/revision-descriptions.md`. Format and
  validate an agent-authored message, then pass the exact value unchanged:

  ```bash
  desc='type(scope): description

  Prior state or constraint, followed by the change in response.'
  desc="$(printf '%s\n' "$desc" | commit-message-format)"
  printf '%s\n' "$desc" | commit-message-check
  git commit --no-edit -m "$desc"
  ```

  Never format an exact user-supplied message. Validate it unchanged and stop if validation fails.

- Rewrite an explicit mutable set in an isolated temporary worktree rooted at the immutable base:
  1. Record the task branch's old tip, confirm it equals the target tip, create a temporary
     directory, and run `git worktree add --detach <temporary-directory> <immutable-base>`.
  2. Reapply each proposed group in dependency order with `git cherry-pick --no-commit <commits>`,
     inspect the resulting diff, stage its intended paths, and create the commit with the validated
     description. To split one source commit by path, apply it with `--no-commit`, unstage it inside
     the isolated worktree with `git restore --staged :/`, and commit each path group. Stop when a
     same-file hunk split or conflict requires interactive resolution. For a one-to-one rewrite,
     preserve the source author identity and author date:

     ```bash
     git commit --author=<author> --date=<author-date> -m "$desc"
     ```

     For a group from one author, preserve that identity and the newest included source author date.
     Stop for explicit direction before combining commits from different authors.

  3. Compare the rebuilt tip tree with the recorded target tree. If they match, atomically move the
     task branch with `git update-ref refs/heads/<branch> <new-tip> <old-tip>`. A concurrent branch
     movement makes this fail safely.
  4. Remove the clean temporary worktree with `git worktree remove <temporary-directory>`. If it is
     not clean, leave it in place and report the blocker rather than forcing removal.

  Do not rewrite the immutable base, merge boundaries, published commits, or commits with uncertain
  ownership. Never perform the rewrite in the user's current worktree.

- Preserve commit dependencies and use the fewest coherent commits. A requested single commit that
  contains independent concerns is a blocker, not permission to obscure them.

## Preserve The Tree And Finish

1. Compare the final `HEAD^{tree}` with the recorded target tree. Any difference means finalization
   changed content and is incomplete.
2. Confirm the index and worktree are clean with `git status --short`. Never clean them with reset,
   checkout, restore, stash, or deletion.
3. Show the ordered commit IDs and full descriptions from the immutable base through `HEAD`.
4. Report rewritten commits, the final branch tip, aggregate-tree preservation, conflicts, and the
   clean worktree. Never push, publish, merge, tag, or release.
