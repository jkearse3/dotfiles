# Schema

`Spec`, `Boundaries`, and `Milestones` are mandatory. `Bookmark:` is the only top-level field before
sections. New contracts use `references/template.md`.

## Structure And Identity

- A contract has at least one milestone. Document order is the required acceptance order; no
  dependency field or parallel eligibility exists.
- Milestone IDs use `M<number>` and are unique. Preserve unaffected IDs during amendment and assign
  new IDs above the highest retained number.
- Every milestone has exactly one `Outcome:` and at least one AC. The outcome is one coherent
  accepted state, not an implementation step or revision boundary.
- AC numbers are globally unique and belong to exactly one milestone. Preserve unaffected numbers
  during amendment and assign new ACs above the highest retained number.
- Agreement data includes milestone identity, title, outcome, AC wording and checks, boundaries, and
  conditional context. AC markers and `Evidence:` are measured state.
- Context and Research are optional. Implementation strategy belongs in planning, not the contract.

## Measured State

AC markers mean:

- `[ ]`: not satisfied. `Evidence:` is `Pending.` before measurement or records the failed result.
- `[x]`: satisfied when last reconciled; the declared `Check:` passed and `Evidence:` records the
  result.
- `[~]`: partially satisfied or only partially verifiable; `Evidence:` states what is established
  and what remains.
- `[!]`: blocked; `Evidence:` names the blocker or user decision needed.

Each AC requires a marker, verifiable outcome, `Check:`, and final `Evidence:` field. `Check:` is
planned proof, not observed evidence. `Evidence:` records only the latest result and must not become
a chronological log. Run the declared check exactly when safe and feasible; do not replace it with
repository exploration or a different check. A failed check produces `[ ]`. An unsafe or unavailable
check produces `[!]` with the exact blocker. Use `[~]` only when the check establishes part of the
AC. Changing an inadequate check requires an approved amendment.

Recorded markers describe the latest reconciliation, not guaranteed current-checkout truth. Status
reports this limitation. Reconciliation establishes current truth only for milestones it measures
during that invocation.

Derive state after validating the schema:

- If every milestone owns only `[x]` ACs, every milestone and the contract are `complete`.
- Otherwise, milestones before the first milestone with a non-`[x]` AC are `complete`.
- The first milestone with a non-`[x]` AC is `next`. It is `blocked` when any owned AC is `[!]`;
  otherwise it is `active`.
- Every later milestone is `waiting`, regardless of its recorded markers, until all earlier
  milestones are complete.

Never persist milestone state, contract state, a selected milestone, summaries, progress queues, or
revision mappings. Recompute them from document order and AC markers whenever needed.

## Coverage And Boundaries

Each milestone describes one coherent accepted outcome. Its ACs jointly prove that outcome. Planning
may choose any coherent implementation approach within the contract boundaries, but should normally
focus on the first incomplete milestone returned by reconciliation.

AC coverage must consider happy paths, errors, edge cases, preserved behavior, repository
conventions, tests, formatting, documentation, and operational effects when relevant. Greenfield
milestones should establish capability in prerequisite order. Brownfield milestones must state the
behavior and invariants preserved during safe transition. Do not add boilerplate criteria for
irrelevant categories.

Use stable anchors such as paths, section names, symbols, configuration keys, commands, and exact
expected observations. Checks should let reconciliation measure an AC directly without searching the
repository for proof.
