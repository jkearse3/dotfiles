---
name: interrogate
description: Pressure-tests plans, designs, ideas, decisions, requirements, scope, and tradeoffs through structured questioning; use when the user wants to interrogate, validate, refine, de-risk, or clarify direction before implementation.
argument-hint: "<topic>"
---

# Interrogate

## Arguments

```
$ARGUMENTS
```

If `$ARGUMENTS` is non-empty, treat it as the topic to interrogate.

If `$ARGUMENTS` is empty, derive the topic from conversation history — look at
what the user just said or what they're working on.

When a topic is obtained (from args or context), open the interrogation by
stating: "Interrogating: <topic>"

When no topic can be derived — neither from args nor from conversation context —
prompt the user: "What would you like to interrogate?" If the user still
provides no topic, stop with an error.

## Execution

Interview me relentlessly about every aspect of this until no uncertainties
remain. Walk down each branch of the decision tree, resolving dependencies
between decisions one-by-one. For each question, provide your recommended
answer. Ask questions one at a time.

If a question can be answered by research (codebase exploration, web search,
etc.), do the research instead of asking.

Systematically probe every dimension of the plan. Question assumptions,
challenge trade-offs, poke at edge cases, trace dependencies, flag risks, demand
a validation strategy, and check that the scope boundaries are right.

Always walk the full branch taxonomy. If a branch is irrelevant, record it as
`N/A` with the reason instead of skipping it silently.

- Problem/invariant: what durable problem must be solved, and what must remain
  true.
- Non-goals: what is explicitly out of scope.
- Stakeholders/consumers: who will use, maintain, depend on, or be affected by
  the result.
- Inputs/context: what information, constraints, and source material are
  available.
- Outputs/content: what the result must contain, omit, preserve, or expose.
- State/lifecycle: when the result is created, updated, invalidated, retired, or
  reused.
- Ownership/boundaries: which actor, system, or layer owns each decision and
  responsibility.
- Dependencies: what upstream or downstream behavior, data, tools, or policies
  must hold.
- Failure modes: how the plan can fail, degrade, be misused, or produce harmful
  ambiguity.
- Examples/counterexamples: concrete in-scope and out-of-scope cases.
- Tradeoffs: alternatives considered, costs accepted, and costs rejected.
- Validation: how success and failure can be checked.
- Revision risk: what future change could make the decisions stale, misleading,
  or unsafe.

Separate implementation choices from durable invariants. For each proposed rule,
constraint, or criterion, ask what problem it solves, whether that problem is
real or speculative, and what would make the rule too broad or too narrow. Keep
choices flexible when the invariant can be preserved by more than one
implementation.

As each branch resolves, record the outcome in a compact artifact. Keep it brief
enough to be used as planning input rather than a transcript.

```
### Decisions

- Decision and rationale.

### Open Questions

- Question, recommended answer if available, and what would resolve it.

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

### N/A Branches

- Branch name: reason it is irrelevant.
```

Before stopping, perform a challenge pass over the resolved artifact. Look for
rules or criteria that are over-broad, too narrow, speculative, contradictory,
untestable, or likely to leak internal mechanics into user-facing output. Ask
follow-up questions or revise the artifact until those issues are resolved.

Stop when every branch is resolved and no open questions remain.
