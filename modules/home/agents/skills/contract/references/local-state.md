# Local State

Resolve the jj root, exactly one current bookmark, bookmark slug, and Markdown
contract path before reading or writing a contract. Stop if the root cannot be
resolved, the current bookmark cannot be resolved, more than one current
bookmark is reported, or the bookmark slug is empty.

A branch contract belongs to exactly one current jj bookmark and has one local
file:

```text
<jj-root>/.agent/contracts/<bookmark-slug>.md
```

Build `<bookmark-slug>` from the current bookmark by replacing every character
outside `A-Za-z0-9._-` with `-`, collapsing repeated `-`, and trimming leading
or trailing `-`. Stop if the result is empty. Stop for user direction if the
derived Markdown path collides with an existing contract for a different
`Bookmark:` value.

Do not create multi-bookmark or stack contracts.

Contract files are untracked local state. Do not add them to Git or jj, and do
not create tracked or exported snapshots.

Keep agreement data, measured AC markers, and `Evidence:` in the Markdown
contract. Do not move milestone metadata, `Check:`, research decisions,
questions, assumptions, or boundaries into another file. Milestone and contract
states are derived, not agreement fields.

Do not create or persist status summaries, selected-milestone state, progress
queues, workflow control files, implementation logs, exported snapshots, or
revision maps.

Before creating or updating a contract file:

1. Create `<jj-root>/.agent/contracts/` if needed.
2. Ensure that directory has an untracked, self-ignoring `.gitignore` with
   whole-directory coverage:

   ```text
   *
   ```

   Create it when absent. If it already exists, inspect it and proceed only when
   its contents and ownership are compatible; never overwrite it.

3. Make jj snapshot the working copy and use `jj status` and targeted
   `jj file list` output to confirm the local `.gitignore` and an existing
   target contract are absent from the snapshot. For a new contract, create and
   verify a temporary representative contract instead, then remove the probe
   before writing the contract.
4. After writing, repeat the jj verification for the actual contract path and
   local `.gitignore`.

Stop for user direction if either path is already tracked, verification would
require untracking an existing path, or the local `.gitignore` cannot be safely
established and verified. Remove only a probe created by this procedure; do not
discard pre-existing content.
