# Derive Next Slice

Use this path when the user asks to derive, refresh, or update the current contract's next
implementation slice.

Read these references before acting:

- `references/local-state.md`
- `references/schema.md`
- `references/next-slice.md`

Deriving a next slice is a measurement operation over the current contract and source of truth. It
may update only measured contract state needed to keep `## Next Slice` accurate.

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
7. Inspect `## Implementation Approach`, `## Boundaries`, and `## Validation` only after measuring
   AC status.
8. If `## Next Slice` is already accurate for the current measured state, leave the contract
   unchanged and summarize it.
9. If `## Next Slice` is stale, update only measured Markdown state needed to keep it accurate: AC
   markers, `Evidence:` lines, `Status:`, `## Next Slice`, and directly verified research question
   or assumption status.
10. If no implementation work remains, set `## Next Slice` to say no implementation slice is pending
    and identify the next useful reconciliation or user-decision step.

Do not edit repository implementation files, workflow state files, skill source, commits, revision
descriptions, bookmarks, or branches. Do not change agreement fields such as `## Context`,
`## Spec`, `## Boundaries`, `## Implementation Approach`, `## Validation`, AC wording, `Check:`
lines, or research decisions.
