# Contract Readiness

Contract creation and amendment end in exactly one readiness state:

- `ready for approval`: the finite checklist below passes; present the draft for explicit approval.
- `blocked on user decision`: an agreement choice affects scope, behavior, boundaries, or proof;
  report the decision needed and stop without writing.
- `blocked on repository evidence`: a claim or check cannot be grounded from available repository
  evidence; report the missing evidence and stop without writing.

Evaluate only this checklist:

- The current bookmark and local contract path are resolved.
- `Spec`, `Boundaries`, `Acceptance Criteria`, and `Validation` are present and internally
  consistent.
- Scope, non-goals, forbidden changes, and stop-before conditions are explicit enough to prevent an
  implementation agent from changing the agreement silently.
- Every AC is an independently verifiable current-checkout outcome with a declared, feasible,
  unambiguous `Check:` and final `Evidence:` field.
- Repository claims needed by the agreement or checks are supported by inspected evidence.
- Any material user choice is resolved; normal implementation details may remain open inside the
  approved boundaries.
- Conditional Context, Research, or Implementation Approach content is included only when needed to
  preserve durable intent, evidence, decisions, constraints, or safe implementation direction.

Complete explicit user requirements may pass directly to `ready for approval`. Inspect repository
facts when the checklist depends on them. Ask only for a material agreement decision. Broad
unresolved product or design uncertainty produces `blocked on user decision`; report the unresolved
decision and stop without expanding contract readiness into product discovery.

Do not write in any blocked state. Approval authorizes the proposed contract-file write and the
minimum directory and repo-local ignore setup required to keep it untracked. It does not authorize
implementation or VCS mutation. A new bookmark requires separate name-and-base confirmation during
the creation procedure's placement phase; contract approval does not provide that authority.
