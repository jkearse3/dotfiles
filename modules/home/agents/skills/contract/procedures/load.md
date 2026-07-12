# Load

Use this path when the user asks to inspect the current contract without reconciling it.

Read these references before acting:

- `references/local-state.md`
- `references/schema.md`

Steps:

1. Resolve Local State.
2. Read the current bookmark contract.
3. Stop if the contract `Bookmark:` value does not match the current bookmark.
4. Summarize the mandatory agreement sections, any present conditional sections, AC marker/evidence
   status, and unsatisfied or blocked ACs.

Loading must not edit any files.
