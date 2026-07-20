# Create

Use this path when arguments are non-empty and no contract exists for the current bookmark.

Read these references before acting:

- `references/local-state.md`
- `references/schema.md`
- `references/template.md`
- `references/readiness.md`

Steps:

1. Resolve Local State. Contract creation never creates, moves, or switches bookmarks; establish the
   intended current bookmark through the applicable version-control workflow first.
2. Verify local ignore or exclude state covers `/.agent/contracts/` and the target would be ignored.
   Do not create directories or change ignore state before approval.
3. Draft the mandatory schema sections and only needed conditional sections. Organize outcomes as
   one or more ordered, coherent milestones with `M<number>` IDs and globally numbered
   milestone-owned ACs.
4. For greenfield work, order capability growth by prerequisite. For brownfield work, inspect and
   record behavior to preserve, safe-transition boundaries, risks, and regression proof when
   relevant. Do not edit implementation files.
5. Give every AC an exact declared check and initialize it to `[ ]` with `Evidence: Pending.`. The
   check must name its expected result and permit direct measurement without open-ended repository
   discovery. Validate ordering, identities, ownership, coherence, boundaries, and checks with
   Contract Readiness.
6. If blocked, report the finite approval-readiness state and blocker and stop. Do not resolve broad
   product or design uncertainty during contract creation.
7. Do not mutate files, directories, ignore state, or version-control state while drafting or
   awaiting approval.
8. Only when readiness is `ready for approval`, present the full draft and ask for explicit user
   approval before writing the contract file.
9. After approval, ensure `.agent/contracts/` exists, establish minimum repo-local ignore state if
   needed, verify the target is ignored, and write the contract atomically.

Creation must not edit implementation files, workflow state other than the approved contract and
required local ignore state, skill source, revisions, revision descriptions, bookmarks, or branches.
