# Reconcile

Use this path when arguments are empty and the current bookmark contract exists.

Read these references before acting:

- `references/local-state.md`
- `references/schema.md`
- `references/next-slice.md`

Reconciliation is an inline, idempotent measurement pass over the current checkout. It compares the
current checkout to the existing Markdown contract and updates only measured Markdown state.

Steps:

1. Resolve Local State.
2. Read the Markdown contract fresh.
3. Stop if the contract `Bookmark:` value does not match the current bookmark. Do not guess or
   rebind the contract.
4. Treat `## Acceptance Criteria`, `## Boundaries`, and `Check:` lines as authoritative.
5. Inspect the current source of truth against every non-superseded AC. Superseded ACs use the `[-]`
   marker and keep their existing evidence.
6. Run cheap relevant `Check:` commands when feasible. Skip checks that are expensive, unsafe,
   require unavailable secrets, or need user setup. Record the limitation in `Evidence:` instead of
   guessing.
7. Update measured Markdown state only: AC markers, `Evidence:` lines, `Status:`,
   `## Current State`, `## Next Slice`, and directly verified research question or assumption
   status.
8. Do not change agreement fields: `## Context`, `## Spec`, `## Boundaries`,
   `## Implementation Approach`, `## Validation Plan`, AC wording, `Check:` lines, or research
   decisions. If the agreement is wrong or incomplete, report that amendment is needed.
9. If no measured Markdown changes are needed, leave the contract unchanged and report that
   reconciliation found no measured updates.

Reconciliation must reflect current code truth. It may mark an AC satisfied when the current
checkout already satisfies it, even if the satisfying change predates the contract or was moved into
a parent revision. It must not require a hard `Base` or `Compare` field. Do not use
unique-vs-inherited ownership detection while reconciling the contract.

Reconciliation must not edit repository implementation files, skill source, workflow state files,
commits, revision descriptions, bookmarks, or branches.
