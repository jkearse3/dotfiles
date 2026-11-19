# Finalize With jj

Use only `jj` syntax established by this procedure or verified against the
installed version. Do not infer template keywords, revset functions, or command
options.

## Inspect And Record

1. Resolve the target set in topological order. For working changes, target `@`.
   For mutable history, require an explicit revset, revision ID, or unambiguous
   task-owned bookmark boundary, and never include the immutable base. Stop if
   the target has descendants outside the task's stack or its affected
   descendants are uncertain. If the target does not end at `@`, require the
   current working-copy revision to be empty and preserve its position through
   finalization.
2. Record the original target tip before mutation:

   ```bash
   old_tip="$(jj log -r <target-tip> --no-graph -T 'commit_id')"
   ```

## Shape The Revisions

If the same file must appear in multiple proposed revisions, a non-interactive
path-only split is insufficient. Combine those revisions unless the user
explicitly provides another safe boundary.

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
  destination, and never cross a dependency, merge, or the authorized target
  set.

Format and validate every description as `references/revision-descriptions.md`
says, then pass the exact validated value unchanged, as in
`jj describe -r <target> -m "$desc"`.

## Preserve The Tree And Finish

Use the diff comparison below as the authoritative tree-preservation check. Do
not replace or supplement it with assumed tree-object template fields.

1. Compare the final tip's tree directly with the original target tip:

   ```bash
   new_tip="$(jj log -r <final-tip> --no-graph -T 'commit_id')"
   tree_diff="$(jj diff --from "$old_tip" --to "$new_tip" --summary)" || exit 1
   test -z "$tree_diff"
   ```

   Any output, command failure, or conflict means finalization is incomplete.

2. Move the task-owned bookmark for this change set, not one that identifies
   only the immutable base or another change set, to the final tip and verify it
   points there. Stop if that bookmark is absent.
3. When the target ended at the pre-finalization `@`, run `jj new <final-tip>`
   and confirm the new `@` is an empty child of the final tip. Otherwise,
   confirm the preserved working-copy revision remains empty after any
   descendant rebasing.
4. Show the result with stable change IDs, commit IDs, and full descriptions:

   ```bash
   jj log -r '<result-set>' --no-pager \
     --template 'change_id.short() ++ " " ++ commit_id.short() ++ "\n" ++ description ++ "\n\n"'
   ```
