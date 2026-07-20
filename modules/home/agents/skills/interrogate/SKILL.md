---
name: interrogate
description: >-
  Interviews the user to resolve material decisions in a plan, decision, or idea. Use proactively
  when shared understanding depends on unresolved intent, ownership, priorities, risk tolerance, or
  tradeoffs, and when the user asks to interrogate, validate, refine, de-risk, clarify, stress-test,
  challenge, or grill their thinking; not for routine factual investigation, implementation
  planning, or ordinary implementation choices.
argument-hint: "<plan, decision, or idea>"
---

# Interrogate

Interview the user about a plan, decision, or idea until you share a precise understanding of it.

## Input

```text
$ARGUMENTS
```

Use the arguments and relevant conversation context to identify the subject. If neither provides
one, ask what should be interrogated and stop.

## Method

1. Establish the subject, intended outcome, and what shared understanding must cover.
2. Treat the subject as a tree of material decisions. A decision is material when a different answer
   could change the outcome, behavior, scope, boundaries, ownership, compatibility, risk,
   validation, or a costly direction.
3. Resolve parent decisions before decisions that depend on them. Select the earliest unresolved
   material decision, and reassess the remaining tree after every answer because branches may
   change, appear, or disappear.
4. Before asking a question, determine what kind of uncertainty it represents:
   - `Discoverable fact`: establish it through safe read-only inspection of the available
     environment instead of asking the user.
   - `User decision`: ask because the answer depends on the user's intent, priorities, ownership, or
     accepted tradeoffs. Never answer it on the user's behalf.
   - `Implementation unknown`: leave it for implementation when it can be resolved safely within the
     agreed boundaries without changing the outcome or material direction.
   - `Non-material assumption`: state it only when it affects interpretation, and record what would
     invalidate it.
5. Ask exactly one question per turn and wait for the answer before continuing. For each question:
   - State the decision being made and any parent decision it depends on.
   - Recommend an answer and explain why.
   - Describe the material tradeoffs.
6. Pressure-test the emerging understanding. Challenge unsupported assumptions, hidden scope
   expansion, speculative requirements, weak boundaries, overlooked failure modes, and validation
   that would not demonstrate the intended outcome. Add questions only when this reveals a material
   decision.
7. Continue until every material decision is resolved and the remaining unknowns are safe to defer
   to implementation.

## Result

Summarize the shared understanding using only sections that carry material information:

```markdown
### Decisions

- Decision and rationale.

### Boundaries

- In-scope and excluded behavior.

### Assumptions

- Non-material assumption and what would invalidate it.

### Implementation Unknowns

- Unknown that can be resolved safely during implementation.
```

Ask the user to confirm that the summary reflects the shared understanding. If the user corrects it,
update the decision tree and continue from the earliest affected decision. Do not plan or act on the
subject before confirmation.

Confirmation ends the interrogation. It does not by itself authorize implementation, persistent
changes, external actions, or version-control mutations.

## Boundaries

- Do not produce an implementation plan, persist workflow state, or perform the described work.
- Do not use a fixed taxonomy or manufacture questions to appear exhaustive. Follow every material
  branch of the actual decision tree and ignore categories that do not create a real decision.
- Do not infer user-owned decisions from defaults, prior behavior, or implementation convenience.
- Treat a vague deferral as unresolved when the decision could change the agreed direction. Explain
  what it blocks, and stop if the user does not want to decide it.
