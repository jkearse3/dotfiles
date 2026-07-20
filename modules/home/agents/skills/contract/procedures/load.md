# Load

Use this path when the user asks for contract status without measurement.

Read these references before acting:

- `references/local-state.md`
- `references/schema.md`

Steps:

1. Resolve Local State and read the current bookmark contract.
2. Stop if `Bookmark:` does not match the current bookmark.
3. Validate the mandatory structure, milestone and AC identities, document order, markers, and
   declared checks. Report an invalid contract and exact defects before deriving state.
4. Derive every milestone state and overall contract state from recorded AC markers and evidence.
5. Summarize the agreement, recorded state, and first incomplete milestone. Keep completed milestone
   detail concise unless requested.

Status uses recorded evidence without remeasuring source. State clearly that it is the latest
recorded observation, not guaranteed current-checkout truth. Do not edit any file or persist derived
state.
