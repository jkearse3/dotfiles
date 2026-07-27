# Finalize With jj

Use this procedure only in a jj repository. The target is either verified
changes in the current working-copy revision or an explicitly authorized mutable
set of unpublished, task-owned revisions.

## Inspect And Record

Use only `jj` syntax established by this procedure or verified against the
installed version. Do not infer template keywords, revset functions, or command
options.

1. Resolve the target set in topological order. For working changes, target `@`.
   For mutable history, require an explicit revset, revision ID, or unambiguous
   task-owned bookmark boundary. Never include the immutable base or a published
   revision.
2. Inspect parents, descendants, bookmarks, full descriptions, per-revision
   diffs, and the aggregate diff. Stop if ownership, publication state, base,
   destination, or affected descendants are uncertain. If the target does not
   end at `@`, require the current working-copy revision to be empty and
   preserve its active position through finalization.
3. Record the immutable base and the original target tip before mutation:

   ```bash
   old_tip="$(jj log -r <target-tip> --no-graph -T 'commit_id')"
   ```

## Shape The Revisions

Start from the complete effective diff. Existing boundaries and order are
evidence, not constraints.

- A revision is coherent when one description explains it as one reviewable
  concern without unrelated clauses.
- Split independent concerns and combine partial steps, tests, documentation,
  configuration, and revision-local fixes that complete one concern.
- Order dependencies first. Otherwise prefer simpler changes before more complex
  changes and fewer files as the final tie-breaker.
- Do not split merely because files differ by type or layer.
- If the same file must appear in multiple proposed revisions, a non-interactive
  path-only split is insufficient. Combine those revisions unless the user
  explicitly provides another safe boundary.
- If single-revision intent conflicts with a coherent result, stop without
  mutation.

Apply structural changes before final descriptions. Use explicit revisions in
every command:

- Split with `jj split -r <target> -m "$desc" <paths>`. Track both resulting
  revisions and rebased descendants after every split; the remainder still needs
  its own final description.
- Squash with
  `jj squash --from <source> --into <destination> --message "$desc"`, or
  `--use-destination-message` only when the destination already has the complete
  final description and discarding the source description is intentional.
- Reorder a linear stack with
  `jj rebase --revision <revision> --insert-after <revision>` or
  `--insert-before <revision>`. Never use `--source` or an ambiguous
  destination, and never cross a dependency, merge, publication boundary, or the
  authorized target set.

Before every command that creates or rewrites a description, read
`references/revision-descriptions.md`, format and validate the complete
agent-authored message, then pass the exact validated value unchanged:

```bash
desc='type(scope): description

Prior state or constraint, followed by the change in response.'
desc="$(printf '%s\n' "$desc" | commit-message format)"
printf '%s\n' "$desc" | commit-message check
jj describe -r <target> -m "$desc"
```

Never format an exact user-supplied message. Validate it unchanged and stop if
validation fails.

## Preserve The Tree And Finish

Use the diff comparison below as the authoritative tree-preservation check. Do
not replace or supplement it with assumed tree-object template fields.

1. Resolve the final tip and compare its tree directly with the original target
   tip:

   ```bash
   new_tip="$(jj log -r <final-tip> --no-graph -T 'commit_id')"
   tree_diff="$(jj diff --from "$old_tip" --to "$new_tip" --summary)" || exit 1
   test -z "$tree_diff"
   ```

   Any output, command failure, or conflict means finalization is incomplete.

2. Move the current task-owned bookmark to the final tip when it is intended to
   identify this stack. Do not move another bookmark or one with uncertain
   ownership.
3. When the target ended at the pre-finalization `@`, create a fresh empty
   working-copy revision with `jj new <final-tip>` and confirm its parent is the
   final tip. Otherwise, preserve the existing working-copy position and confirm
   it remains empty after any descendant rebasing.
4. Show the result with stable change IDs, commit IDs, and full descriptions:

   ```bash
   jj log -r '<result-set>' --no-pager \
     --template 'change_id.short() ++ " " ++ commit_id.short() ++ "\n" ++ description ++ "\n\n"'
   ```

Report rebased descendants, moved task-owned bookmarks, aggregate-tree
preservation, conflicts, and the preserved or newly created empty working-copy
revision. Never publish bookmarks or revisions.
