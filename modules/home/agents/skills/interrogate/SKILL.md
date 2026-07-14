---
name: interrogate
description: Establishes scope alignment by pressure-testing outcomes, boundaries, constraints, non-goals, and validation; use proactively when a consequential or complex action task lacks alignment or a material change invalidates it, and when the user asks to interrogate, validate, refine, de-risk, or clarify direction.
argument-hint: "<topic>"
---

# Interrogate

## Arguments

```
$ARGUMENTS
```

If `$ARGUMENTS` is non-empty, treat it as the topic to interrogate.

If `$ARGUMENTS` is empty, derive the topic from conversation history — look at what the user just
said or what they're working on.

When a topic is obtained (from args or context), open the interrogation by stating: "Interrogating:
<topic>"

When no topic can be derived — neither from args nor from conversation context — prompt the user:
"What would you like to interrogate?" If the user still provides no topic, stop with an error.

## Execution

Evaluate the topic exhaustively, but escalate questions selectively. Walk every relevant branch of
the decision tree and resolve dependencies in order. Do not make the user answer questions that
available evidence or a safe, obvious default can resolve.

Inspect relevant evidence before asking. Research factual questions directly through codebase
exploration, documentation, web search, or other available read-only sources. Resolve a branch
without asking when the evidence supports one answer or a default has no material downside. Record
the evidence or rationale so the resolution is not an implicit assumption.

Ask the user only when the answer:

- Has multiple viable choices with consequential pros and cons.
- Depends on their intent, priorities, risk tolerance, or ownership decision.
- Is costly to reverse or materially affects correctness, scope, safety, or compatibility.
- Cannot be established from available evidence without accepting material risk.

For each user question, provide a recommendation, its rationale, and the relevant tradeoffs. Ask
dependent questions one at a time. Batch independent questions when doing so does not obscure their
consequences.

Systematically probe every dimension of the plan. Question assumptions, challenge tradeoffs, test
edge cases, trace dependencies, flag risks, require a validation strategy, and verify that scope
boundaries are explicit.

Always walk the full branch taxonomy. Give every branch one explicit disposition instead of silently
skipping it:

- `Resolved from evidence`: the outcome and supporting evidence.
- `Resolved by safe default`: the outcome, rationale, and why alternatives have no material benefit.
- `User decision required`: the choices, recommendation, and consequential tradeoffs.
- `Not applicable`: why the branch does not affect this topic.
- `Deferred`: why the question is non-blocking and what would resolve it later.

- Problem/invariant: what durable problem must be solved, and what must remain true.
- Non-goals: what is explicitly out of scope.
- Stakeholders/consumers: who will use, maintain, depend on, or be affected by the result.
- Inputs/context: what information, constraints, and source material are available.
- Outputs/content: what the result must contain, omit, preserve, or expose.
- State/lifecycle: when the result is created, updated, invalidated, retired, or reused.
- Ownership/boundaries: which actor, system, or layer owns each decision and responsibility.
- Dependencies: what upstream or downstream behavior, data, tools, or policies must hold.
- Failure modes: how the plan can fail, degrade, be misused, or produce harmful ambiguity.
- Examples/counterexamples: concrete in-scope and out-of-scope cases.
- Tradeoffs: alternatives considered, costs accepted, and costs rejected.
- Validation: how success and failure can be checked.
- Revision risk: what future change could make the decisions stale, misleading, or unsafe.

Separate implementation choices from durable invariants. For each proposed rule, constraint, or
criterion, ask what problem it solves, whether that problem is real or speculative, and what would
make the rule too broad or too narrow. Keep choices flexible when the invariant can be preserved by
more than one implementation.

As each branch resolves, record the outcome in a compact artifact. Keep it brief enough to be used
as planning input rather than a transcript. Do not treat a material unresolved choice as an
assumption or defer it merely to finish the interrogation.

```
### Decisions

- Decision and rationale.

### User Decisions

- Decision, viable choices, recommendation, and consequential tradeoffs.

### Assumptions

- Assumption, why it is acceptable, and what would invalidate it.

### Non-goals

- Explicitly excluded scope.

### Examples

- Concrete in-scope cases.

### Counterexamples

- Concrete out-of-scope or invalid cases.

### Risks

- Risk, consequence, and mitigation.

### Validation Strategy

- How the result can be checked.

### Candidate Criteria

- Generic criteria the final plan or design should satisfy.

### Deferred Questions

- Non-blocking question, why it can wait, and what would resolve it.

### Branch Coverage

- Branch: disposition and concise rationale.
```

Before stopping, perform an integrity pass over the resolved artifact. Verify that every taxonomy
branch has a disposition and look for unsupported assumptions, omitted dependencies or failure
modes, contradictory decisions, untestable criteria, unsafe defaults, and rules that are over-broad
or too narrow. Resolve issues from evidence when possible and ask the user only when the correction
requires a consequential design choice.

Stop when every branch has a justified disposition, no user decision remains unanswered, and the
integrity pass finds no material hole. Deferred questions must be explicitly non-blocking.
