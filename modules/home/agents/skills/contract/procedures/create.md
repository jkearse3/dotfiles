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
3. Verify that local ignore or exclude state covers `/.agent/contracts/` and that the target path
   would be ignored. Do not create directories or change ignore state before approval.
4. Draft the mandatory schema sections and only the conditional sections needed by the agreement.
   Inspect repository facts required by the readiness checklist. Do not edit implementation files.
5. Complete the draft from the user intent, resolved decisions, and current repo facts. Ensure every
   AC has an exact declared check and pending evidence.
6. Evaluate Contract Readiness against the complete draft. If blocked, report the finite readiness
   state and blocker and stop. Treat broad unresolved product or design uncertainty as
   `blocked on user decision`; do not resolve it as part of contract creation.
7. Do not mutate files, directories, ignore state, or VCS state while drafting or awaiting approval.
8. Only when readiness is `ready for approval`, present the full draft and ask for explicit user
   approval before writing the contract file.
9. After approval, ensure `.agent/contracts/` exists, establish the minimum repo-local ignore state
   if needed, verify the target path is ignored, and write the contract file.

Creation must not edit repository implementation files, workflow state files other than its approved
contract and required local ignore state, skill source, commits, revision descriptions, bookmarks,
or branches.
