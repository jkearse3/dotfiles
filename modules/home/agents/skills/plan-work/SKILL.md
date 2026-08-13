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
3. Reload every authoritative input and inspect current repository or system
   state needed to compare it with the planning baseline. Report incidental
   drift and continue. Stop on material drift, report why the plan now needs
   reconciliation, and do not flag it persistently unless that was separately
   requested.
4. Treat the plan as the complete alignment input and follow its work sequence,
   validation, finalization, and review under the applicable repository or
   operational workflow. Do not recover intent from prior conversation or reopen
   decisions the plan settles unless current evidence invalidates them.
5. Never edit, annotate, archive, rename, delete, or record execution state on
   the plan while consuming it.

### Update Or Reconcile

1. Resolve and read the complete plan. Retain the content read as the update
   baseline.
2. Reload every authoritative input and inspect current state far enough to find
   material drift. Do not perform diagnostics that may mutate state, notify
   people, incur cost, acquire resources, or otherwise have external effects.
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
   material observations under `Current State` and make every external fact on
   which execution depends reloadable under `Authoritative Inputs`.
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
   not guarantee, record the observable invariant under `Completion Conditions`
   and require a durable check or reviewer-rerunnable proof under `Validation`.
   Put consequential choices under `Design` and residual exposure under
   `Risks And Recovery`. Use `references/artifact-contracts.md` as prompts, not
   as a checklist; do not copy prompts or explain irrelevant omissions.
5. Resolve architecture, interfaces, data flow, and consequential strategy
   choices. Record decisions and rationale so execution does not reopen them.
   Prescribe implementation details when correctness, compatibility, safety,
   external effects, review boundaries, user intent, or later work depends on
   them. State what remains executor discretion so detail does not accidentally
   constrain inconsequential choices.
6. Sequence the fewest coherent work concerns that produce the outcome. Give
   each concern its purpose, concrete changes, preserved behavior, dependencies,
   implementation requirements, discretion, and focused validation. Name exact
   files, symbols, interfaces, procedures, algorithms, edge cases, and failure
   handling when reconnaissance establishes them and execution depends on them;
   do not invent speculative targets. Keep code, tests, documentation,
   configuration, and operational work together when they support one result.
   For repository mutations, use expected independently reviewable revision
   concerns. Authority for the complete request does not combine independent
   concerns. Assign at most one concern to each mutating delegation.
7. Define validation from the completion conditions and material risks. End each
   repository concern with focused verification and finalization, and place
   aggregate review after the last repository concern rather than between them.
   Identify integration checks that genuinely require later concerns. Prefer
   commands, observations, inspections, responses, or other signals that prove
   behavior rather than merely proving steps ran.
8. Perform a completeness pass across every standard section. Use `None` with a
   short reason when a section is not applicable; never omit a standard section
   or collapse an actual plan into a one-sentence working update.

## Authoritative Inputs

Authoritative inputs are external owners of facts or requirements that ground
the plan and must be reloaded to execute it safely. The plan itself owns the
intended outcome, scope, established user decisions, selected design,
implementation requirements, and work sequence. Current source, specifications,
contracts, policies, schemas, API documentation, and safely rederived state keep
their existing ownership.

For each input, record:

- `Governs`: the fact, requirement, interface, or constraint it owns.
- `Relevant Areas`: stable headings, symbols, endpoints, or outputs to inspect;
  prefer these over fragile line numbers.
- `Planning Baseline`: the material facts observed during reconnaissance.
- `Reload`: the read-only action that obtains current state. Put mutating or
  externally consequential verification under `Validation`, not here.
- `Material Drift`: changes that would invalidate the outcome, scope, design,
  sequencing, requirements, or validation and require reconciliation.

The baseline records evidence; it never replaces the current source. A prior
conversation, a timestamp, a digest, or a revision identifier alone is not an
authoritative input. Preserve material conversation context directly in the
plan. Plans that need portable, shared, reviewable, or long-term authority must
use a tracked specification, contract, or issue instead of the ignored local
store.

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

Incidental drift does not require reconciliation. Report it and continue when it
cannot affect the plan's outcome, scope, requirements, design, sequence, or
validation. Discovering material drift does not itself authorize editing a
persisted plan: report the needed flag in the response unless the user
explicitly requested `flag`, `update`, or `reconcile`.

## Output

Every plan uses the complete structure below. Keep detail proportional within
the sections, but do not omit headings, combine sections, or substitute a brief
working update. Repeat the `Authoritative Inputs` and `Work Sequence` entries as
needed.

```markdown
# Plan: <concise outcome>

Status: Ready | Blocked | Needs Reconciliation

## Outcome

<Final state and user-visible or operational effect.>

## Current State

- `<source>`: <Observed fact and its consequence for this plan.>

## Scope

- <Included behavior, systems, people, and artifacts.>

## Exclusions

- <Adjacent work or behavior this plan must not change.>

## Constraints

- <Invariant, compatibility requirement, policy, or limit.>

## Completion Conditions

- <Observable final state, preserved invariant, or required effect.>

## Design

### Architecture

<Component boundaries, responsibilities, control flow, and dependencies.>

### Interfaces And Data

<APIs, types, schemas, configuration, persistence, inputs, and outputs.>

### Decisions

- **<Decision>:** <Choice, rationale, rejected alternatives when material, and
  consequences.>

### Implementation Requirements

- <Detail every executor must follow exactly.>

### Executor Discretion

- <Choice intentionally left to implementation judgment.>

## Work Sequence

### 1. <Coherent work concern>

**Purpose:** <Why this concern is needed and its expected result.>

**Changes:**

- <Specific behavior, files, symbols, interfaces, or procedures to change.>

**Preserve:**

- <Existing behavior and invariants that must remain intact.>

**Dependencies:**

- <Required preceding concern or external prerequisite.>

**Implementation Requirements:**

- <Algorithms, edge cases, failure handling, migration, cleanup, or other
  mandatory details.>

**Executor Discretion:**

- <Safe local choices left open.>

**Validation:**

- `<focused command, inspection, response, or signal>`: <What it proves before
  dependent work proceeds.>

## Validation

- `<end-to-end, integration, regression, static, or manual check>`: <Completion
  condition or material risk it establishes.>

## Risks And Recovery

- **<Failure mode>:** <Prevention, recovery, or rollback.>

## Authority And Approvals

- <Permission or confirmation required before consequential action and its
  provenance.>

## Stop Conditions

- <Discovery requiring reassessment, reconciliation, or user direction.>

## Authoritative Inputs

### `<path, URL, command, or system identifier>`

**Governs:** <Fact, requirement, interface, or constraint this source owns.>

**Relevant Areas:** <Stable headings, symbols, endpoints, or outputs.>

**Planning Baseline:** <Material facts observed while preparing the plan.>

**Reload:** <Safe command or inspection that obtains current state.>

**Material Drift:** <Change that requires plan reconciliation.>

## Assumptions

- <Safe assumption and what would invalidate it.>

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

Use `None: <reason>` under `Reconciliation Required` unless the status is
`Needs Reconciliation`. Use `None: <reason>` under `Decisions Needed` unless the
status is `Blocked`. A `Ready` plan has neither unresolved material decisions
nor reconciliation work.

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
