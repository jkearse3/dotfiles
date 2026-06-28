# Readiness

## Interactive Planning

Planning is consensus-seeking. Do not request activation approval until the agent and user are
aligned on outcome, scope, boundaries, acceptance criteria, and validation.

Resolve uncertainty using the narrowest sufficient method:

- Inspect repo facts, patterns, tests, and current behavior directly.
- Ask one direct user question when one missing decision blocks planning.
- Run an alignment pass when the desired outcome is conceptual, branching, high-stakes, or consensus
  is not yet clear.
- Persist a draft plan only when it is useful as a shared artifact, not as a premature activation
  approval request.

Before creating a planning state or activating one, reduce material uncertainty.

Material uncertainty is any unknown that could change ACs, boundaries, scope, behavior,
architecture, data handling, security, UX, `Check:` methods needed to prove ACs, or a costly
mutation direction.

Before implementation, audit whether ACs cover requested outcomes, current behavior,
approach-implied behavior, risks, negative constraints, boundaries, assumptions, and `Check:`
methods.

Every non-invalidated AC must have a feasible `Check:` before activation. `Check:` is the planned
proof path, not observed evidence. Missing, unsafe, ambiguous, or infeasible `Check:` lines are
material uncertainty.

Reduce uncertainty by matching the method to the unknown. Inspect repo facts, patterns, tests, and
current behavior first. Ask the user when the answer is a decision, not a repo fact. Use an
alignment pass for broad, branching, high-stakes, or not-yet-aligned decisions.

Do not re-spec or expand requested work. ACs and boundaries are the execution contract. If they are
incomplete, contradictory, or too ambiguous to implement safely, return to planning or ask instead
of inventing scope.

Boundaries are iteration-specific and do not need a fixed subsection schema or exact file allowlist.
They are ready when implement can decide mutate-or-block and verify can confirm compliance from the
state file plus permitted repo inspection.

If scope is discoverable, boundaries must name the repo relationship that makes discovered files,
systems, or behavior in scope. Broad placeholders like "as needed" or "related files" are not enough
unless that relationship is defined.

If material uncertainty remains before activation, do not set `Status: active`, `Next: implement`.
Keep or create `Status: planning`, `Next: planning`, record concrete questions, and stop. If no safe
planning draft can be written, ask before state-file creation instead.

Normal implementation unknowns may remain when they can be answered safely by reading, mutating, and
checking within boundaries.

## Activation Readiness Gate

Before requesting activation approval, confirm all approval-relevant uncertainty is resolved.

Approval-relevant uncertainty includes any unknown that could change ACs, boundaries, scope,
mutation targets, verification commands, user-visible behavior, persisted data or configuration,
external services, VCS lifecycle actions, or implementation direction with meaningful tradeoffs.

For each open item, classify it as one of:

- Repo fact: resolve by read-only inspection before approval.
- User decision: ask the user before approval.
- Normal implementation unknown: safe to resolve during implementation within boundaries.

Do not request activation approval if any repo fact or user decision remains unresolved. Open
assumptions are allowed only when they are non-material, explicitly recorded, and safe to invalidate
during implementation without changing ACs, boundaries, or approval scope.
