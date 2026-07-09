# Slice Selection

Use this reference only when the user asks for a next implementation slice. Slice selection is a
read-only proposal derived from the contract and the current checkout. It must not write
`## Next Slice`, create task queues, or otherwise persist workflow state.

Before proposing a slice, read the contract and inspect enough current source of truth to understand
which ACs are unsatisfied, partial, or blocked. Treat `## Acceptance Criteria`, `## Boundaries`,
`## Implementation Approach`, `## Validation`, and `Check:` lines as authoritative. If the contract
lacks enough context to choose safely, say what is missing and recommend amending the contract.

When work remains, propose the next reviewable implementation-ready slice that advances unsatisfied
or partial ACs while staying independently verifiable. Prefer a slice with one primary review
question. Do not choose a slice that mixes unrelated risk areas unless separating them would create
artificial scaffolding or make the result harder to verify. Slice by reviewable risk area and
user-visible behavior, not by maximum size, estimated size, file count, task count, or the smallest
possible change.

Use this pattern in the response:

```markdown
Make the next reviewable change that advances the next unsatisfied acceptance criteria.

Target AC: <number or numbers>

Do this by <specific implementation boundary>.

Stop before <nearest ambiguity, unrelated behavior, or agreement change>.

Verify with <cheap check or inspection>.
```

Do not add size labels, time estimates, task queues, or mechanical file-by-file checklists. When no
implementation work remains, say that no implementation slice is pending and identify the next
useful reconciliation or user-decision step.
