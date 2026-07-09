# Contract Readiness

Contract creation and amendment are discovery-first and consensus-seeking. Do not request approval
to write a contract until the agent and user agree there are no approval-relevant holes in the
branch agreement.

Before approval, pressure-test the agreement from multiple angles:

- Intended behavior, affected users or agents, and explicit non-goals.
- Existing behavior, compatibility expectations, and current-state facts.
- Edge cases, negative cases, failure modes, and recovery behavior.
- Data, configuration, persistence, security, privacy, and trust-boundary implications.
- User-visible behavior, developer-facing behavior, docs, tests, and operational effects.
- Boundaries, stop-before conditions, assumptions, decisions, and open questions.
- Relevant repo facts, likely touch points, implementation approach, and non-obvious constraints.
- AC coverage, AC wording, and whether every `Check:` proves the AC without interpretation.
- Validation coverage and whether completion can be measured without session memory.
- Whether a fresh implementation agent could propose a reviewable next slice without guessing
  agreement details.

A contract must be self-contained for a fresh agent with no session memory. Before approval, check
whether a future agent could understand the user intent, relevant repo facts, agreed behavior,
implementation direction, boundaries, validation path, and current state using only the contract and
the current checkout. If not, keep drafting or ask targeted questions before writing.

Resolve uncertainty using the narrowest sufficient method. Inspect repo facts, patterns, tests,
docs, and current behavior directly when the answer is discoverable. Ask the user when the answer is
a decision. Prefer sequential questions when each answer may change which question or concern should
be raised next; batch only independent questions.

Treat these as approval blockers: vague ACs, vague or infeasible `Check:` lines, unclear boundaries,
missing edge cases, unsafe assumptions, unresolved user decisions, ambiguous current-state claims,
missing implementation-relevant context, stale or unsupported repo facts, incomplete validation, or
insufficient context for a fresh implementation agent to propose a safe next slice lazily.

Normal implementation unknowns may remain only when they can be resolved safely inside the approved
boundaries without changing ACs, checks, stop-before conditions, or user-visible behavior. Record
them as assumptions if future agents need to know they exist.
