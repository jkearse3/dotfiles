---
name: plan-work
description: >-
  Creates, refines, or validates proportionate working plans for any kind of actionable work,
  including implementation, investigation, review, documentation, external operations, and mixed
  tasks. Use when a working plan needs to be established, refined, or validated, even when a small
  task needs only a one-sentence plan, and when the user asks to plan, scope, prepare, sequence, or
  make work portable to another context. Do not use for purely conversational responses, decision
  pressure-testing, or when an adequate working plan is already explicit in the conversation.
argument-hint: "<outcome, request, or existing plan>"
---

# Plan Work

Produce a self-contained plan that establishes what to do, what not to do, and
how to know the outcome was achieved. Planning is read-only and owns no
persistent workflow state.

## Input

```text
$ARGUMENTS
```

Use the arguments and relevant conversation context to identify the intended
outcome. If neither provides a planning target, ask for one and stop.

## Method

1. Establish the intended outcome, affected targets, and completion boundary.
   Distinguish the requested result from possible implementation details.
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
   explicitly.
5. Sequence the fewest coherent actions that produce the outcome. For repository
   mutations, group actions into expected independently reviewable concerns.
   Define each concern by its outcome, dependencies, and focused validation
   rather than exact files or hunks. A broader acceptance milestone may contain
   multiple concerns, while code, tests, documentation, and configuration that
   support one concern may remain together. Authority for the complete request
   does not combine independent concerns. Assign at most one concern to each
   mutating delegation. Preserve implementation freedom where multiple
   approaches satisfy the same invariant; make a choice explicit when later
   actions depend on it.
6. Define validation from the outcome and material risks. End each repository
   concern with focused verification, finalization, and review before the next
   concern begins. Explicitly identify integration checks that genuinely require
   later concerns and retain them for task completion. Prefer concrete commands,
   observations, inspections, or acceptance signals that establish behavior
   rather than merely proving that steps ran.
7. Perform a proportional completeness pass across the lenses below. Resolve or
   report every material gap, but omit irrelevant categories and empty sections
   from the written plan.

Completeness lenses:

- Outcome and completion condition.
- Current state and authoritative evidence.
- Targets, users, stakeholders, and ownership.
- Inputs, outputs, interfaces, and content boundaries.
- In-scope work and explicit non-goals.
- Constraints, invariants, compatibility, and policy.
- Dependencies, prerequisites, ordering, and parallelism.
- Failure modes, downstream effects, recovery, and reversibility.
- Permissions, approvals, visibility, and external impact.
- Validation, acceptance, and regression protection.
- Stop conditions, escalation points, assumptions, and freshness risks.

## Readiness

A plan is `Ready` only when it is actionable and no unresolved material decision
prevents safe execution. If evidence or a user decision is required first,
return `Blocked`, state exactly what is needed, and do not disguise assumptions
as a complete plan.

Keep depth proportional. A small task may need one sentence naming the action,
validation, and exclusion. Complex or consequential work needs enough detail
that a fresh session could execute the plan after reloading its authoritative
inputs.

## Output

Use this structure flexibly. A one-sentence small plan may combine its outcome,
scope, action, and validation. Otherwise include those four sections in every
ready plan and include other sections only when they carry material information.

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

### Actions

1. <Ordered action, purpose, and material dependency. For repository mutations, identify the expected
   revision concern and focused validation.>

### Validation

- `<command or inspection>`: <what it establishes.>

### Risks And Recovery

- <Failure mode, prevention, and recovery or rollback.>

### Authority And Approvals

- <Permission or confirmation required before consequential action.>

### Stop Conditions

- <Condition requiring reassessment or user direction.>

### Authoritative Inputs

- `<path, URL, system, or document>`: <what an executing session must reload.>

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
