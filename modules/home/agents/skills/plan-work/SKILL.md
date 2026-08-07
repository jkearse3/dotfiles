---
name: plan-work
description: >-
  Creates, refines, or validates proportionate working plans for any kind of
  actionable work, including implementation, investigation, review,
  documentation, external operations, and mixed tasks. Use when a working plan
  needs to be established, refined, or validated, even when a small task needs
  only a one-sentence plan, and when the user asks to plan, scope, prepare,
  sequence, or make work portable to another context. Do not use for purely
  conversational responses, decision pressure-testing, or when an adequate
  working plan is already explicit in the conversation.
argument-hint: "<outcome, request, or existing plan>"
---

# Plan Work

Produce a self-contained, evidence-grounded execution proposal that establishes
the intended outcome, boundaries, approach, work sequence, and proof of
completion. The plan makes the proposed attack visible for user-agent alignment
while preserving implementation freedom where specific choices do not matter.
Planning is read-only and owns no persistent workflow state.

## Input

```text
$ARGUMENTS
```

Use the arguments and relevant conversation context to identify the intended
outcome. If neither provides a planning target, ask for one and stop.

## Method

1. Establish the intended outcome, affected targets, and observable completion
   conditions. Distinguish the requested result from possible implementation
   details. When an authoritative contract or specification exists, consume its
   requirements without redefining its acceptance criteria.
2. Inspect relevant code, documents, systems, history, or external sources
   through safe read-only methods. Resolve available facts directly. Do not
   perform a diagnostic action when it may mutate state, notify people, incur
   cost, acquire resources, or otherwise have external effects.
3. Identify consequential uncertainty. Resolve factual questions from evidence,
   use safe defaults only when alternatives have no material consequence, and
   ask the user when intent, ownership, risk tolerance, compatibility, scope, or
   reversibility controls the answer. Resolve broad direction-setting before
   completing the plan rather than absorbing decision pressure-testing into
   planning.
4. Determine the smallest complete scope. Trace affected consumers,
   dependencies, stakeholders, interfaces, persisted state, and operational
   effects far enough to include necessary work and exclude adjacent work
   explicitly. When work introduces or changes an artifact or instruction that a
   person or another system invokes or depends on, identify the actual consumer
   contract, where it is established, and what it requires. Derive failure modes
   reachable through the artifact's inputs, outputs, state changes, lifecycle,
   and integration context. For each material behavior that construction does
   not guarantee, record the observable invariant under `Completion Conditions`
   and require a durable check or reviewer-rerunnable proof under `Validation`.
   Put consequential choices under `Design` and residual exposure under
   `Risks And Recovery`. Use `references/artifact-contracts.md` as prompts, not
   as a checklist; do not copy prompts or explain irrelevant omissions.
5. Select an approach that resolves consequential strategy choices and explain
   why it fits the evidence, constraints, and outcome. Commit to implementation
   details only when correctness, compatibility, safety, external effects, or
   later work depends on them. Otherwise preserve execution freedom.
6. Sequence the fewest coherent work concerns that produce the outcome. Define
   each concern by its purpose, expected result, material dependencies, and
   focused validation rather than speculative files, symbols, or hunks. Keep
   code, tests, documentation, configuration, and operational work together when
   they support one result. For repository mutations, use expected independently
   reviewable revision concerns. Authority for the complete request does not
   combine independent concerns. Assign at most one concern to each mutating
   delegation.
7. Define validation from the completion conditions and material risks. End each
   repository concern with focused verification and finalization, and place
   review after the last repository concern rather than between them. Explicitly
   identify integration checks that genuinely require later concerns and retain
   them for task completion. Prefer concrete commands, observations,
   inspections, responses, or other signals that establish behavior rather than
   merely proving that steps ran.
8. Perform a proportional completeness pass across the lenses below. Resolve or
   report every material gap, but omit irrelevant categories and empty sections
   from the written plan.

Completeness lenses:

- Outcome and completion conditions.
- Current state and authoritative evidence.
- Targets, users, stakeholders, and ownership.
- Inputs, outputs, interfaces, and content boundaries.
- In-scope work and explicit non-goals.
- Constraints, invariants, compatibility, and policy.
- Dependencies, prerequisites, ordering, and parallelism.
- Failure modes, downstream effects, recovery, and reversibility.
- Permissions, approvals, visibility, and external impact.
- Approach, work sequence, and implementation freedom.
- Validation, completion evidence, and regression protection.
- Stop conditions, escalation points, assumptions, and freshness risks.

## Readiness

A plan is `Ready` only when it is actionable and no unresolved material decision
prevents safe execution. If evidence or a user decision is required first,
return `Blocked`, state exactly what is needed, and do not disguise assumptions
as a complete plan.

Keep depth proportional. A small task may need only a compact statement of the
outcome, scope, completion conditions, approach, work, validation, and any
exclusion. Complex or consequential work needs enough detail that a fresh
session could execute the plan after reloading its authoritative inputs.

## Output

Use this structure flexibly. Every ready plan conveys its outcome, scope,
completion conditions, approach, work sequence, and validation, but related
concepts may be combined and headings omitted when a compact plan is clearer.
Include other sections only when they carry material information.

```markdown
## Plan: <concise outcome>

Status: Ready | Blocked

### Outcome

<The state that should exist when the work is complete.>

### Current State

- `<source>`: <observed fact and consequence for the plan.>

### Scope

- <Included behavior, systems, people, or artifacts.>

### Exclusions

- <Adjacent work or behavior this plan must not change.>

### Constraints

- <Invariant, compatibility requirement, policy, or limit.>

### Completion Conditions

- <Observable final state, preserved invariant, or required effect.>

### Approach

<Selected technical or operational strategy and why it fits the evidence and
constraints. Identify prescribed implementation details only when material.>

### Work Sequence

1. **<Coherent work concern>.** <Purpose, expected result, and material
   dependencies. Identify prescribed implementation or procedure only when
   material, and name the focused validation required before dependent work
   proceeds.>

### Validation

- `<command, inspection, response, or signal>`:
  <completion condition or material
  risk it establishes.>

### Risks And Recovery

- <Failure mode, prevention, and recovery or rollback.>

### Authority And Approvals

- <Permission or confirmation required before consequential action.>

### Stop Conditions

- <Condition requiring reassessment or user direction.>

### Authoritative Inputs

- `<path, URL, system, or document>`: <what an executing session must reload,
  and the command that rederives it when the work rebuilds it.>

### Assumptions

- <Safe assumption and what would invalidate it.>

### Decisions Needed

- <Decision, recommendation, and material tradeoff.>
```

## Boundaries

- Do not execute the plan, edit artifacts, mutate external systems, or mutate
  version-control state while planning.
- Do not persist the plan or create a task registry, progress marker, approval
  record, or other workflow state. A separate user request may authorize another
  operation to persist the plan.
- Do not copy authoritative acceptance criteria into a competing plan-level
  agreement. Reference or summarize them as completion boundaries and leave
  durable acceptance checks, evidence, and measured state with their owning
  contract or specification.
- Do not expand the requested outcome to satisfy the completeness lenses or turn
  normal implementation details into user decisions.
- Do not treat the plan as implementation authority. A prior request may already
  authorize action; otherwise planning alone authorizes no mutation.
- If implementation is already authorized, the ready plan becomes the current
  alignment input and normal execution may continue under governing rules. If
  the user requested planning rather than execution, stop after the plan.
- Replan only when the requested outcome changes or material evidence
  invalidates the current scope, approach, or validation. Do not replan each
  execution step.
