# Fulfill

Use this path only when the user clearly directs implementation of an existing current-bookmark
contract. Literal `fulfill` syntax is not required. Equivalent imperative language includes "satisfy
the contract," "finish this contract," "implement the remaining acceptance criteria," "make the
current contract pass," and "carry out the contract."

Questions, hypotheticals, status requests, and ambiguous references do not authorize fulfillment.
For example, "is the contract satisfied," "what remains," "can we satisfy this contract," and "how
would you finish it" are read-only or require clarification. Use one-revision mode only when the
request clearly says `fulfill once` or otherwise limits implementation to one coherent revision.

Read these references before acting:

- `references/local-state.md`
- `references/schema.md`
- `references/iteration.md`

Fulfillment is the only contract operation authorized to edit implementation files. It orchestrates
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
   requires amendment or user direction. In one-revision mode, narrow or replan before editing when
   the slice is not expected to produce exactly one coherent revision, and stop if doing so is
   unsafe.
6. Reconcile the contract again from the finalized checkout. Do not mark an AC satisfied unless its
   declared check passes or the schema explicitly permits partial/manual evidence.
7. In one-revision mode, stop after this reconciliation. Otherwise, return to step 3 and continue
   until completion or a stop condition is reached.

When stopping, report the contract status, revisions finalized in order, AC changes, verification
and review performed, and the exact completion or stop reason. Do not describe blocked or partially
verified work as complete.
