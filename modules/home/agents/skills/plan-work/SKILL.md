---
name: plan-work
description: >-
  Creates, persists, reads, refines, validates, or reconciles standardized,
  evidence-grounded execution plans for implementation, investigation, review,
  documentation, external operations, and mixed work. Use when a plan needs to
  be established, saved, updated, checked against current authoritative inputs,
  or made executable by a fresh session. Do not use for purely conversational
  responses, decision pressure-testing, or ordinary brief working updates when
  an adequate execution plan is already explicit.
argument-hint: "<outcome, request, or .agent/plans plan>"
---

# Plan Work

Produce a self-contained, evidence-grounded execution proposal that preserves
all material intent, decisions, boundaries, implementation requirements, work
sequence, and proof of completion needed by a fresh session. Ground the proposal
in reloadable authoritative inputs without copying those inputs into a competing
source of truth.

A plan is a proposal, not execution authority, workflow state, or an approval
record. Creating, persisting, updating, validating, or reconciling a plan never
authorizes the work it describes.

## Input

```text
$ARGUMENTS
```

Use the arguments and relevant conversation context to identify the requested
operation and planning target. If neither identifies a target, ask for one and
stop.

## Operations

Default to creating or refining a plan in the response without persisting it.
File mutation requires explicit user language:

- `persist`, `save`, or equivalent language creates a new persisted plan.
- `update` or equivalent language naming an existing plan rewrites that exact
  plan without changing its path.
- `reconcile` naming an existing plan reloads its authoritative inputs, resolves
  material drift, and rewrites that exact plan when resolution is possible.
- `flag` or equivalent language naming an existing plan may persist
  `Needs Reconciliation` and its reconciliation details without resolving them.
- `read`, `show`, or `validate` alone is read-only. Report needed changes in the
  response and do not modify the plan.
- `execute` or `run` naming an existing plan consumes it under authority
  supplied by the current request or another independently authorized task. The
  plan itself supplies no execution authority.

Do not infer persistence from requests to plan, prepare, refine, or make work
portable. Do not automatically persist a plan before creating a handoff, teach
another skill about plan storage, or create a handoff unless the user separately
and explicitly requests it.

`tests/plan-scripts.sh` is maintainer validation, not part of normal skill
operation. Run it only when modifying this skill or when the user explicitly
requests that test.

### Persist

1. Complete the plan before reserving storage. A `Blocked` plan may be persisted
   when the user explicitly requests it; unresolved material decisions must
   remain visible.
2. Choose a concise lowercase kebab-case slug for the outcome. Run
   `scripts/prepare-path.sh --workspace <target-repo> <slug>`, passing the
   absolute path of the repository you are working in as `<target-repo>`. Invoke
   the script by its path; it is independent of the current working directory
   and never derives the target from where it runs. It resolves canonical
   storage, safely prepares the ignored store, atomically reserves a new empty
   timestamped plan file, and prints its absolute path. If it reports ambiguous
   storage or a safety failure, stop and report the error rather than bypassing
   it.
3. Write the complete standardized plan directly to the reserved empty file.
4. Report the absolute path. Persistence itself does not authorize the described
   work; continue only when the user separately authorized execution.

### Resolve

When the request provides an exact plan filename or path, run
`scripts/resolve-plan.sh --workspace <target-repo> <exact-filename-or-canonical-path>`,
passing the absolute path of the repository you are working in as
`<target-repo>`, to validate it. Invoke the script by its path; it is
independent of the current working directory. The script accepts only a regular,
non-symlink file directly inside the canonical store.

Otherwise, list valid plans by running the resolver with no plan identifier:
`scripts/resolve-plan.sh --workspace <target-repo>`.

Infer the intended plan only from descriptive filename wording and relevant
conversation context; do not read plan contents during selection. Never use a
timestamp, mtime, listing order, lexical order, collision suffix, or assumed
latest or active plan as a tie-breaker. If exactly one candidate is clearly
intended, pass its exact path or filename back to the script for validation. If
no candidate is plausible or multiple candidates remain plausible, ask the user
to identify the plan before reading or mutating any plan. Selection does not
grant authority beyond the governing request, and canonical-store validation
must never be bypassed.

### Execute

Execution requires an explicit execute or run request identifying one plan.

1. Resolve and read the complete plan. Confirm the current request or another
   independently authorized task covers its outcome, scope, and consequential
   effects. Stop if the plan would broaden that authority.
2. Require `Status: Ready`. Stop on `Blocked` or `Needs Reconciliation` and
   report the unresolved section without editing the plan.
3. Reload every material source and compare current state with both the planning
   baseline and planned target using the classifications under
   `Sources And Drift`. Continue after a baseline refresh or expected plan
   delta, adjusting only the remaining work. Stop only on plan-invalidating
   drift, report the affected plan claim, and do not flag it persistently unless
   that was separately requested.
4. Treat the plan as the complete alignment input and follow its work sequence,
   validation, finalization, and review under the applicable repository or
   operational workflow. Do not recover intent from prior conversation or reopen
   decisions the plan settles unless current evidence invalidates them.
5. Never edit, annotate, archive, rename, delete, or record execution state on
   the plan while consuming it.

### Update Or Reconcile

1. Resolve and read the complete plan. Retain the content read as the update
   baseline.
2. Reload every material source and compare current state with both the planning
   baseline and planned target using the classifications under
   `Sources And Drift`. Incorporate baseline refreshes and expected plan deltas
   directly. Resolve plan-invalidating drift in the rebuilt plan, or mark it
   `Blocked` when required evidence or a consequential decision is unavailable.
   Do not perform diagnostics that may mutate state, notify people, incur cost,
   acquire resources, or otherwise have external effects.
3. Rebuild the complete plan rather than appending notes or an execution log.
   Preserve its path and creation timestamp. Keep settled decisions unless new
   evidence invalidates them.
4. Immediately before writing, reread the plan. If it differs from the update
   baseline, stop and report the conflict rather than overwriting it.
5. Replace the complete plan at the same path in one edit. Report the path and
   material changes. Do not execute the plan, archive it, rename it, or create a
   successor automatically.

## Method

1. Establish the intended outcome, affected targets, and observable completion
   conditions. Distinguish the requested result from possible implementation
   details. When an authoritative contract or specification exists, consume its
   requirements without redefining its acceptance criteria.
2. Perform as much safe reconnaissance as needed to make a fresh session
   executable without recovering material context. Inspect relevant code,
   documents, systems, history, consumers, tests, and external sources. Record
   only observations that affect the plan under `Context`. Give every external
   dependency an exact, reloadable locator.
3. Identify consequential uncertainty. Resolve factual questions from evidence,
   use safe defaults only when alternatives have no material consequence, and
   ask the user when intent, ownership, risk tolerance, compatibility, scope, or
   reversibility controls the answer. Resolve direction-setting before marking
   the plan `Ready`; never rely on prior conversation as an authoritative input.
4. Determine the smallest complete scope. Trace affected consumers,
   dependencies, stakeholders, interfaces, persisted state, and operational
   effects far enough to include necessary work and exclude adjacent work
   explicitly. When work introduces or changes an artifact or instruction that a
   person or another system invokes or depends on, identify the actual consumer
   contract, where it is established, and what it requires. Derive failure modes
   reachable through the artifact's inputs, outputs, state changes, lifecycle,
   and integration context. For each material behavior that construction does
   not guarantee, record the observable result under `Acceptance Criteria` and
   require a durable check or reviewer-rerunnable proof under work-level
   `Validate` or `Final Validation`. Use `references/artifact-contracts.md` as
   prompts, not as a checklist; do not copy prompts or explain irrelevant
   omissions.
5. Resolve architecture, interfaces, data flow, and consequential strategy
   choices. Record decisions and rationale so execution does not reopen them.
   Prescribe implementation details when correctness, compatibility, safety,
   external effects, review boundaries, user intent, or later work depends on
   them. Use an optional `Design` section only when these choices cross work
   items or need explanation beyond a requirement. Leave inconsequential choices
   unstated rather than enumerating executor discretion.
6. Sequence the fewest coherent work concerns that produce the outcome. Give
   each concern exact targets and concrete changes. Add preserved behavior,
   dependencies, failure handling, and stage-gate validation only when they are
   material to that concern. Name exact files, symbols, interfaces, procedures,
   algorithms, and edge cases when reconnaissance establishes them and execution
   depends on them; do not invent speculative targets. Keep code, tests,
   documentation, configuration, and operational work together when they support
   one result. For repository mutations, use expected independently reviewable
   revision concerns. Authority for the complete request does not combine
   independent concerns. Assign at most one concern to each mutating delegation.
7. Define validation from the completion conditions and material risks. End each
   concern with validation only when dependent work needs that proof. Put
   end-to-end and aggregate checks under `Final Validation`; do not repeat the
   same command or expected result at work, acceptance, and final-validation
   levels. Generic repository finalization and review remain governed by the
   applicable instructions and belong in the plan only when task-specific
   revision boundaries or review evidence matter.
8. Perform an isolation pass rather than a heading-completeness pass. A fresh
   executor reading only the plan and its exactly named sources must be able to
   identify the workspace, prerequisites, intended result, exclusions, settled
   decisions, mandatory invariants, ordered work, proof of success, and the
   conditions that require stopping. Omit inapplicable optional sections and
   fields; never add `None` placeholders merely to fill the template.

## Sources And Drift

Authoritative inputs are external owners of facts or requirements that ground
the plan and must be reloaded to execute it safely. The plan itself owns the
intended outcome, scope, established user decisions, selected design,
implementation requirements, and work sequence. Current source, specifications,
contracts, policies, schemas, API documentation, and safely rederived state keep
their existing ownership.

Classify each material source by its actual role:

- `Contract`: owns an external requirement, interface, policy, or acceptance
  boundary.
- `Current implementation`: establishes the edit baseline and behavior to
  preserve or change.
- `Validation evidence`: demonstrates behavior but does not own that behavior.
- `Precedent`: suggests an approach but may be replaced without invalidating the
  plan.
- `Operational state`: establishes a mutable prerequisite, topology, access
  condition, or sequencing fact.

Use `Sources And Drift` only for mutable inputs on which safe execution depends.
For each entry, record its role, the exact fact it owns or establishes, the
material baseline observed during planning, a read-only reload action, and a
testable `Reconcile Only If` predicate. Add `Expected Plan Delta` when the plan
intentionally changes the baseline or may find its target already implemented.
Use exact repository-relative paths and stable symbols or headings for
repository sources; identify the workspace separately. Use exact URLs, issue
IDs, commands, endpoints, versions, or system identifiers for external sources.
Do not bundle unrelated authorities into one entry.

The baseline records evidence; it never replaces the current source. A prior
conversation, a timestamp, a digest, or a revision identifier alone is not an
authoritative input. Preserve material conversation context directly in the
plan. Plans that need portable, shared, reviewable, or long-term authority must
use a tracked specification, contract, or issue instead of the ignored local
store.

Do not classify drift from a changed file, version, location, command, test, or
baseline alone. First compare current state with both the recorded baseline and
the planned target:

- `No relevant change`: continue.
- `Baseline refresh`: the observation is stale, but the outcome, boundaries,
  decisions, requirements, work, and proof remain valid. Retarget the affected
  details and continue.
- `Expected plan delta`: current state already contains some or all planned
  work. Verify compatible behavior and ownership, skip redundant work, and
  continue.
- `Plan-invalidating drift`: current evidence falsifies a required invariant,
  changes external authority or requirements, broadens consumers or effects,
  makes the design or sequence unsafe, invalidates required proof, or requires a
  new consequential decision. Reconcile before affected execution.

A change is material only when the executor can name the affected scope
boundary, decision, requirement, work dependency, acceptance criterion,
authority, or validation claim and explain why the plan can no longer satisfy it
safely. Changes outside a source's named area are incidental unless dependency
tracing establishes that impact. Version changes require reconciliation only
when a capability on which the plan depends changed. Repository workflow changes
are refreshed automatically unless they alter authority, prohibit a planned
effect, invalidate an essential revision boundary, or remove required proof.

Use this conflict order:

1. The current user request or an independently authorized task governs
   execution authority; the plan never does.
2. External contracts and specifications continue to own their requirements and
   acceptance criteria.
3. The plan owns the approved interpretation, decisions, and execution strategy.
4. Current source owns existing behavior except where the plan explicitly
   changes it.
5. A material conflict requires reconciliation rather than silent improvisation.

## Readiness And Reconciliation

- `Ready`: the plan is actionable and no unresolved material decision prevents
  safe execution. Any choice not prescribed is explicitly safe to leave to the
  executor.
- `Blocked`: required evidence or a material user decision is missing. State
  exactly what is needed; do not disguise assumptions as a complete plan.
- `Needs Reconciliation`: a previously formed plan conflicts materially with
  current authoritative inputs or repository state. State the conflict and stop
  affected execution until the plan is reconciled.

Baseline refreshes and expected plan deltas do not require reconciliation.
Report them when they materially change residual work, then continue.
Discovering plan-invalidating drift does not itself authorize editing a
persisted plan: report the needed flag in the response unless the user
explicitly requested `flag`, `update`, or `reconcile`.

## Output

Every plan uses the standard sections below. Optional sections and fields are
marked explicitly. Keep detail proportional: exhaustiveness means no material
execution context is missing, not that every possible heading is present. Repeat
`Work` and `Sources And Drift` entries as needed.

```markdown
# Plan: <concise outcome>

Status: Ready | Blocked | Needs Reconciliation

Workspace: <repository or system identity>; planned at `<absolute path>`

## Outcome

<Final state and user-visible or operational effect.>

## Context

- `<exact source or Decision>`: <Material fact, requirement, settled choice, and
  its consequence.>

## Before Starting

- <Optional: access, approval, prerequisite, authority, or stop condition not
  already expressed by a source entry. Reference source entries instead of
  repeating their reload actions.>

## Scope

### Included

- <Behavior, systems, people, and artifacts affected.>

### Excluded

- <Adjacent work or behavior this plan must not change.>

## Requirements

- <Invariant, compatibility boundary, safety rule, or mandatory design choice.>

## Design

<Optional: cross-cutting architecture, interfaces, data flow, ownership,
migration, or sequencing decisions.>

## Work

### 1. <Coherent work concern>

**Targets:** <Exact files, symbols, systems, or procedures where known.>

**Changes:**

- <Specific implementation, documentation, configuration, migration, or
  operational work, including mandatory edge and failure handling.>

**Preserve:**

- <Optional: non-obvious existing behavior or state that must remain intact.>

**Dependencies:**

- <Optional: prerequisite not already obvious from the ordered sequence.>

**Validate:**

- <Optional: stage-gate command or observation required before dependent work.>

## Acceptance Criteria

- <Observable final state, preserved invariant, or required effect.>

## Final Validation

- `<end-to-end, integration, regression, static, or manual check>`: <Expected
  result and the acceptance criterion or material risk it proves.>

## Risks And Recovery

- **<Optional material failure mode>:** <Prevention, recovery, or rollback.>

## Sources And Drift

### `<path, URL, command, or system identifier>`

**Role:** Contract | Current implementation | Validation evidence | Precedent |
Operational state

**Owns Or Establishes:** <Exact source-owned requirement, interface, invariant,
or fact.>

**Baseline:** <Material fact observed while preparing the plan.>

**Expected Plan Delta:** <Optional intended difference from the baseline.>

**Reload:** <Read-only action and stable area that obtain current state.>

**Reconcile Only If:** <Testable change that invalidates a named plan claim and
why it prevents safe execution.>

## Reconciliation Required

### <Concise conflict>

**Detected From:** `<authoritative input>`

**Planning Baseline:** <What the plan expected.>

**Current State:** <What is now true.>

**Impact:** <Affected scope, decision, concern, or validation.>

**Required Resolution:** <Evidence, decision, or plan revision needed.>

## Decisions Needed

- <Unresolved decision, recommendation, and material tradeoff.>
```

`Before Starting`, `Design`, `Risks And Recovery`, and `Sources And Drift` are
optional when the work has no material content for them. `Preserve`,
`Dependencies`, and `Validate` are optional within a work item. Include
`Reconciliation Required` only for `Needs Reconciliation` and `Decisions Needed`
only for `Blocked`. A `Ready` plan omits both. Never add an empty section or
`None` placeholder.

## Boundaries

- Do not execute the plan, edit implementation artifacts, mutate external
  systems, or mutate version-control state while planning.
- Without explicit persistence language, planning is read-only. The only
  mutations authorized by explicit plan persistence or maintenance are the named
  files below `.agent/plans/` and safe creation of that ignored store.
- Keep `.agent/plans/` entirely ignored and untracked. Never treat it as a task
  registry or add progress, completion, ownership, ancestry, approval, execution
  records, automatic lifecycle transitions, or an inferred active plan.
- Do not copy authoritative acceptance criteria into a competing plan-level
  agreement. Reference or summarize them as completion boundaries and leave
  durable acceptance checks, evidence, and measured state with their owner.
- Do not expand the requested outcome to fill the schema or turn normal
  implementation details into user decisions.
- Do not treat the plan as implementation authority. A prior request may already
  authorize action; otherwise planning alone authorizes no mutation beyond an
  explicitly requested plan-file operation.
- If implementation is already authorized, a `Ready` plan may be used as the
  current alignment input and execution may continue under governing rules. If
  the user requested planning or plan maintenance rather than execution, stop
  after the plan operation.
- Do not edit, complete, archive, rename, or delete a persisted plan during its
  execution. Replan only when the requested outcome changes or material evidence
  invalidates the current plan.
