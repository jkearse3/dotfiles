# Iterate

Use this path only when the arguments explicitly request `iterate` or `iterate once` for an existing
current-bookmark contract.

Read these references before acting:

- `references/local-state.md`
- `references/schema.md`
- `references/iteration.md`

Iteration is the only contract operation authorized to edit implementation files. It orchestrates
the approved agreement; applicable implementation and version-control rules govern every repository
mutation, revision, verification, review, and bookmark action. This procedure does not replace or
relax those rules and must not silently alter the agreement.

Steps:

1. Resolve Local State and read the contract fresh. Stop if it is missing or its `Bookmark:` value
   does not match the current bookmark.
2. Reconcile every non-superseded AC against current source and its exact declared `Check:` when
   safe and feasible. Update only measured contract state allowed by `references/schema.md`.
3. Stop if reconciliation makes the contract `complete` or `blocked`, or shows that the agreement
   needs amendment.
4. Inspect enough source and repository state to derive the next slice using
   `references/iteration.md`. Before editing, state its target ACs, intended transition, intended
   base, primary review question, preserved invariants, stop boundary, and focused verification. The
   slice is ephemeral and must not be added to the contract.
5. Implement and finalize only that slice under the applicable implementation and version-control
   rules. Replan its implementation or boundary when `references/iteration.md` permits; stop when it
   requires amendment or user direction. For `iterate once`, narrow or replan before editing when
   the slice is not expected to produce exactly one coherent revision, and stop if doing so is
   unsafe.
6. Reconcile the contract again from the finalized checkout. Do not mark an AC satisfied unless its
   declared check passes or the schema explicitly permits partial/manual evidence.
7. For `iterate once`, stop after this reconciliation. For `iterate`, return to step 3 and continue
   until completion or a stop condition is reached.

When stopping, report the contract status, revisions finalized in order, AC changes, verification
and review performed, and the exact completion or stop reason. Do not describe blocked or partially
verified work as complete.
