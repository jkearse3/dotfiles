# Amend

Use this path when arguments are non-empty and a contract exists, or when reconciliation shows the
agreement itself is wrong, incomplete, or stale.

Read these references before acting:

- `references/local-state.md`
- `references/schema.md`
- `references/readiness.md`
- `references/next-slice.md`

Amendment changes the agreement. Reconciliation measures code against the existing agreement. Keep
that distinction explicit.

During reconciliation, update only measured state: AC markers, evidence, status, next-step guidance,
and directly verified research question or assumption status.

Amendment may update `## Context`, `## Spec`, `## Boundaries`, `## Implementation Approach`,
`## Validation`, AC wording, research decisions, or add and supersede ACs. It requires explicit user
approval before writing.

Before approval, run Contract Readiness against the amended agreement. If approval-relevant holes
remain, ask the next question or present the unresolved concern and stop before writing. Do not ask
for amendment approval until the agent and user agree the amended contract has no approval-relevant
holes.

After approval, write only the contract file. Do not edit repository implementation files, workflow
state files, skill source, commits, revision descriptions, bookmarks, or branches while amending.

Rules for AC changes:

- Never renumber ACs.
- If an AC already has evidence or likely related work, supersede it with `[-]` and add a
  replacement AC with a new number.
- Tiny wording clarifications may edit an AC in place only when the meaning does not change.
- Do not silently rewrite `## Context`, `## Spec`, `## Boundaries`, `## Implementation Approach`,
  `## Validation`, AC wording, or existing decisions during reconciliation. Propose an amendment
  instead.
