# How Blockers Show Up in Code

Common code defects, each under its `findings.md` blocker type. Each one is a
finding only under `findings.md`'s rules: someone gets hurt, on a real path.

## `behavior`

- **A state the code admits but mishandles.** The target introduces or widens a
  representation that allows a state the code does not support. Report it only
  when you can cite a producer, meaning a path that builds the state or nothing
  that prevents it, and a consumer that mishandles it or silently falls into a
  default branch.
- **Uniqueness or a cross-record reference enforced only in application code.**
  Concurrent writers race past the check and store duplicates or dangling
  references. Skip invariants a data-store constraint already enforces.
- **An error nobody can trace.** A runtime error that an operator will chase,
  raised without enough stable context to find where it came from, or with an
  error code, event name, or log key built so it cannot be searched as a
  literal.

## `coverage`

- **A check that proves less than it claims.** A mock or fake offered as proof
  that the code works with an external system, when it only restates the code's
  own assumptions, leaves that behavior unprotected.

## `safety`

- **A check that reads or changes production, shared, or other non-disposable
  state.** Running the checks can damage or leak real data.

## `text`

- **A misleading durable name.** A misleading name on a public API, a stored
  field, or anything else that outlives the change costs a migration to fix once
  the target reaches the default branch; say so in the finding.
