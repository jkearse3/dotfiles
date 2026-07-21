# Contract Readiness

Contract creation and amendment end in exactly one readiness state:

- `ready for approval`: the finite checklist below passes; present the draft for explicit approval.
- `blocked on user decision`: an agreement choice affects scope, behavior, boundaries, milestone
  shape, order, or proof; report the decision needed and stop without writing.
- `blocked on repository evidence`: a claim or check cannot be grounded from available repository
  evidence; report the missing evidence and stop without writing.

These approval-readiness labels are not derived contract or milestone state and are never stored in
the contract.

Evaluate only this checklist:

- The current bookmark and local contract path are resolved.
- `Bookmark:`, `Spec`, `Boundaries`, and `Milestones` are present and internally consistent, with no
  persisted contract or milestone state.
- At least one milestone exists, IDs are unique `M<number>` values, and each milestone has exactly
  one outcome and at least one AC.
- Milestone order is a sensible acceptance sequence. Each earlier outcome is safe to require before
  considering the next milestone.
- Every AC number is globally unique and owned by exactly one milestone.
- Unaffected milestone and AC identities are preserved during amendment. New identities are above
  the highest retained number.
- Every AC is a verifiable outcome with a safe, feasible, unambiguous `Check:` and final `Evidence:`
  field. The check includes its expected result and does not require open-ended rediscovery.
- Each milestone outcome and its ACs describe one coherent acceptance boundary rather than unrelated
  changes or implementation tasks.
- Scope, non-goals, forbidden changes, and stop-before conditions prevent an implementation agent
  from silently changing milestone boundaries or the agreement.
- Greenfield work grows capability in document order. Brownfield work states existing behavior,
  preservation constraints, transition risks, and regression proof when relevant.
- Repository claims needed by the agreement or checks are supported by inspected evidence.
- Any material user choice is resolved; normal implementation details may remain open inside an
  approved milestone boundary.
- Conditional Context or Research content exists only when needed to preserve durable intent,
  evidence, decisions, or constraints.

Complete explicit user requirements may pass directly to `ready for approval`. Inspect repository
facts when the checklist depends on them. Ask only for a material agreement decision. Broad
unresolved product or design uncertainty produces `blocked on user decision`; report the unresolved
decision and stop without expanding readiness into product discovery.

Do not write in any blocked approval-readiness state. Approval authorizes the proposed contract-file
write and minimum local directory and self-ignoring `.gitignore` setup needed to keep both
untracked. It does not authorize implementation or version-control mutation.
