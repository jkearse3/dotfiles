# Propose Slice

Use this path when the user asks to propose the next implementation slice from the current contract.

Read these references before acting:

- `references/local-state.md`
- `references/schema.md`
- `references/slice-selection.md`

Proposing a slice is read-only. It derives guidance from the contract and current checkout, then
returns the proposal to the user. It must not edit the contract, repository implementation files,
workflow state files, skill source, commits, revision descriptions, bookmarks, or branches.

Steps:

1. Resolve Local State.
2. Read the Markdown contract fresh.
3. Stop if the contract `Bookmark:` value does not match the current bookmark. Do not guess or
   rebind the contract.
4. Treat `## Acceptance Criteria`, `## Boundaries`, and `Check:` lines as authoritative.
5. Inspect the current source of truth enough to know which non-superseded ACs are unsatisfied,
   partial, or blocked.
6. Inspect `## Implementation Approach`, `## Boundaries`, and `## Validation` before choosing a
   slice.
7. Return a next-slice proposal using `references/slice-selection.md`, or explain why the contract
   needs amendment before a safe slice can be chosen.
