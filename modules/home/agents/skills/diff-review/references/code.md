# Code Defect Tests

Load `coding-style` and apply these tests to the code the target changes, for
any author, citing each section by name. Each test reports a finding under
SKILL.md's Findings rules.

- **Names:** a name is a finding only when it fails a concrete test: its natural
  reading misstates the concept's meaning, units, or semantics; it omits a unit
  or other semantics its type does not carry (`timeoutMs`, not `timeout`); it is
  a boolean whose true case is ambiguous; it no longer matches the behavior; it
  spells a concept the target spells differently elsewhere; it breaks a parallel
  with its siblings; or it conflicts with the repository's vocabulary.
  Preferring another accurate name is not a finding. A failing durable name, as
  Treat Durable Names as Decisions lists them, costs a migration to rename once
  the target is reachable from the default branch; say so in the finding.
- **Make Invalid States Unrepresentable:** report a representation the target
  introduces or widens that admits a state the code does not support, only when
  you can cite a producer (a path that builds the state, or nothing that
  prevents it) and a consumer that mishandles it or silently falls into a
  default branch. Uniqueness or a cross-record reference enforced only in
  application code is a `bug`, because concurrent writers race past it. Skip
  types the target leaves untouched, invariants a data-store constraint already
  enforces, and corrections needing machinery the repository does not use.
- **Preserve Operational Trails:** a runtime error without enough stable context
  to locate its source; an error code, event name, or log key built so it cannot
  be searched as a literal; a retained legacy API with no deprecation pointer to
  its supported path.
- **Document Symbol Contracts:** a new or materially changed public symbol whose
  failure behavior, units, side effects, or concurrency a caller cannot learn
  without reading its implementation. A missing docstring alone is not a
  finding.
- **Write Durable Checks:** a mock or fake offered as proof of external
  compatibility that only restates assumptions is `coverage`. A check that reads
  or mutates production, shared, or non-disposable state is `safety`.
- **Unrelated churn:** renames, whitespace-only changes, and API changes the
  target's purpose does not need, as Check the Result lists them, are `clarity`.

Unless the request, the Context input, or the repository's own instructions
adopt them, `coding-style`'s layout rules and naming preferences beyond the
Names tests are never findings. Keep the Change Minimal is never a finding
beyond dead material and unrelated churn; leave reuse and speculative generality
to `diff-refine`.
