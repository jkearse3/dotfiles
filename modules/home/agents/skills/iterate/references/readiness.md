# Readiness

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

Reduce uncertainty by matching the helper to the unknown. Inspect repo facts, patterns, tests, and
current behavior first. Ask the user when the answer is a decision, not a repo fact. Use
`investigate` for broad or multi-step technical discovery and `interrogate` for broad, branching, or
high-stakes decisions when those helpers are available and the task shape warrants them.

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
Keep or create `Status: planning`, `Next: none`, record concrete questions, and stop. If no safe
planning draft can be written, ask before state-file creation instead.

Normal implementation unknowns may remain when they can be answered safely by reading, mutating, and
checking within boundaries.
