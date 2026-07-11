# Create

Use this path when arguments are non-empty and no contract exists for the current bookmark.

Read these references before acting:

- `references/local-state.md`
- `references/schema.md`
- `references/readiness.md`

Steps:

1. Confirm the user already chose whether this contract uses the current bookmark or a new bookmark.
   If not, return to the runbook's bookmark decision and stop before drafting.
2. Resolve Local State.
3. Ensure `.agent/contracts/` exists and local ignore or exclude state covers `/.agent/contracts/`.
   Verify the target contract path is ignored locally before writing it.
4. Run Contract Readiness. Inspect enough repository facts to draft detailed context, boundaries,
   research findings, implementation approach, validation, ACs, and checks. Do not edit
   implementation files.
5. If approval-relevant holes remain, ask the next question or present the unresolved concern and
   stop before writing the contract file. Continue this loop until the agent and user agree the
   branch agreement has no approval-relevant holes.
6. Draft a contract from the user intent, resolved decisions, and current repo facts.
7. Include detailed context, concrete boundaries, research findings/decisions/questions/assumptions,
   implementation approach, validation, and verifiable ACs. Make the contract exhaustive enough that
   a fresh implementation agent can propose a next slice lazily from the contract and current
   checkout.
8. Present the full draft and ask for explicit user approval before writing the contract file.
9. After approval, write only the contract file.

Creation must not edit repository implementation files, workflow state files, skill source, commits,
revision descriptions, bookmarks, or branches.
