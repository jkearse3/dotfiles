# Local State

Resolve the jj root, exactly one current bookmark, bookmark slug, and Markdown contract path before
reading or writing a contract. Stop if the root cannot be resolved, the current bookmark cannot be
resolved, more than one current bookmark is reported, or the bookmark slug is empty.

A branch contract belongs to exactly one current jj bookmark and has one local file:

```text
<jj-root>/.agent/contracts/<bookmark-slug>.md
```

Build `<bookmark-slug>` from the current bookmark by replacing every character outside
`A-Za-z0-9._-` with `-`, collapsing repeated `-`, and trimming leading or trailing `-`. Stop if the
result is empty. Stop for user direction if the derived Markdown path collides with an existing
contract for a different `Bookmark:` value.

Do not create multi-bookmark or stack contracts.

Contract files are untracked local state. Do not add them to Git or jj, and do not create tracked or
exported snapshots.

Keep the human agreement and measured state in the Markdown contract. Do not move `Status:`, AC
markers, `Check:`, `Evidence:`, current-state notes, next-step guidance, research decisions,
questions, assumptions, or boundaries into another file. Do not create additional workflow-control
files or queues.

Before creating a contract file:

1. Create `<jj-root>/.agent/contracts/` if needed.
2. Ensure repo-local ignore or exclude state covers the whole contracts directory:

   ```text
   /.agent/contracts/
   ```

   In this git-backed setup, prefer `<jj-root>/.git/info/exclude` so the ignore rules stay local.

3. Verify the target contract path is ignored before writing it.

Stop for user direction if the ignore or exclude rule cannot be written, if the target path cannot
be verified as ignored, or if the repository uses a different local-ignore mechanism that is
unclear.
