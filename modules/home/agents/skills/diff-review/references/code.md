# How the Findings Questions Show Up in Code

Common code defects, each under the Findings question it answers. Each one is a
finding only under SKILL.md's Findings rules: someone gets hurt, on a real path.

## Question 2: does it work, and does everything else still work?

- **A state the code admits but mishandles.** The target introduces or widens a
  representation that allows a state the code does not support. Report it only
  when you can cite a producer, meaning a path that builds the state or nothing
  that prevents it, and a consumer that mishandles it or silently falls into a
  default branch.
- **Uniqueness or a cross-record reference enforced only in application code.**
  Concurrent writers race past the check and store duplicates or dangling
  references. Skip invariants a data-store constraint already enforces.
- **A check that proves less than it claims.** A mock or fake offered as proof
  that the code works with an external system, when it only restates the code's
  own assumptions, leaves that behavior unprotected.
- **An error nobody can trace.** A runtime error that an operator will chase,
  raised without enough stable context to find where it came from, or with an
  error code, event name, or log key built so it cannot be searched as a
  literal.

## Question 3: is it safe?

- **A check that reads or changes production, shared, or other non-disposable
  state.** Running the checks can damage or leak real data.

## Question 4: does its text hold up?

- **A name that leads a caller to misuse it.** Its plain reading misstates what
  it means, omits a unit its type does not carry (`timeoutMs`, not `timeout`),
  leaves unclear what `true` means for a boolean, or no longer matches the
  behavior. Preferring another accurate name is not a finding. A bad name on a
  public API, a stored field, or another name that outlives the change costs a
  migration to fix once the target reaches the default branch; say so in the
  finding.
