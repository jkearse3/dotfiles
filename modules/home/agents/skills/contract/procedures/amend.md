# Amend

Use this path when the user clearly asks to change an existing agreement, or when reconciliation
shows the agreement itself is wrong, incomplete, or stale.

Read these references before acting:

- `references/local-state.md`
- `references/schema.md`
- `references/readiness.md`

Amendment changes the agreement. Reconciliation measures code against the existing agreement. Keep
that distinction explicit.

During reconciliation, update only measured state: AC markers, evidence, status, and directly
verified research question or assumption status.

Amendment may update `## Context`, `## Spec`, `## Boundaries`, `## Implementation Approach`,
`## Validation`, AC wording, research decisions, or add and supersede ACs. It requires explicit user
approval before writing.

Before approval, run Contract Readiness against the amended agreement. If blocked, report the finite
readiness state and blocker and stop before writing. Broad unresolved product or design uncertainty
is `blocked on user decision` and remains outside amendment. Only when readiness is
`ready for approval` may the full amendment be presented for explicit approval.

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
