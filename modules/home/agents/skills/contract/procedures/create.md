# Create

Use this path when arguments are non-empty and no contract exists for the current bookmark.

Read these references before acting:

- `references/local-state.md`
- `references/schema.md`
- `references/readiness.md`

Steps:

1. Confirm the user already chose whether this contract uses the current bookmark or a new bookmark.
   If not, return to the runbook's bookmark decision and stop before drafting.
2. When the user chooses a new bookmark, complete this placement phase before resolving Local State:
   - Resolve and inspect the repository, working-copy revision and parent, bookmarks pointing at the
     working copy, default bookmark, proposed bookmark name, and intended base.
   - Ask for a proposed name when none is explicit. Infer the intended base only when the applicable
     VCS rules establish it unambiguously; in particular, preserve the positioned parent of an empty
     working copy rather than substituting the default bookmark.
   - Stop for user direction if the proposed bookmark already exists, the base is ambiguous,
     unrelated changes would be displaced or inherited, or placement would require rewriting history
     or moving an existing bookmark.
   - Confirm the proposed name and intended base with the user. This confirmation authorizes only
     placing the working copy on that base and creating the named bookmark for it.
   - Place the working copy on the confirmed base, create and switch to the new bookmark, then
     verify that it is the only current bookmark and that its working-copy parent is the confirmed
     base. Stop with the exact blocker if either postcondition fails.
3. Resolve Local State.
4. Verify that local ignore or exclude state covers `/.agent/contracts/` and that the target path
   would be ignored. Do not create directories or change ignore state before approval.
5. Draft the mandatory schema sections and only the conditional sections needed by the agreement.
   Inspect repository facts required by the readiness checklist. Do not edit implementation files.
6. Complete the draft from the user intent, resolved decisions, and current repo facts. Ensure every
   AC has an exact declared check and pending evidence.
7. Evaluate Contract Readiness against the complete draft. If blocked, report the finite readiness
   state and blocker and stop. Treat broad unresolved product or design uncertainty as
   `blocked on user decision`; do not resolve it as part of contract creation.
8. After placement, do not mutate files, directories, ignore state, or further VCS state while
   drafting or awaiting approval.
9. Only when readiness is `ready for approval`, present the full draft and ask for explicit user
   approval before writing the contract file.
10. After approval, ensure `.agent/contracts/` exists, establish the minimum repo-local ignore state
    if needed, verify the target path is ignored, and write the contract file.

Creation must not edit repository implementation files, workflow state files other than its approved
contract and required local ignore state, skill source, revision descriptions, or branches. It must
not mutate revisions or bookmarks except to create the empty working-copy revision and new bookmark
authorized by the placement phase.
