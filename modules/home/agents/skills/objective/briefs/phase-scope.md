# Phase Scope Brief

## Instructions

Read the objective at `.objectives/_current/00-main.md` and propose the next phase. On a valid
proposal, write the phase file at the absolute path provided by the orchestrator.

### Step 1: Read State

The orchestrator provides the following inputs in the prompt:

- `objective_dir` — absolute path to the active objective directory
- `P` — next phase number (matches the `## Phases` index entry)
- `NN` — next sequence number for the phase filename
- `Phase file` — absolute path to the phase file to write (i.e., `<objective_dir>/NN-phase-P.md`)

Read these sections from `00-main.md`:

- `## Acceptance Criteria` — read all ACs and their markers
- `## Approach` — implementation roadmap
- `## Research` — findings, decisions, questions, assumptions
- `## Phases` index — then use Phase Resolution for each phase: if the index entry has a markdown
  link, read that file; otherwise read the inline `## Phase N:` section in `00-main.md`. Review
  prior learnings, completed task patterns, issues encountered.

If a file already exists at the provided phase-file path, read it — this is a refinement round and
the file holds the prior draft's approach and tasks. Carry that context forward when producing the
revised proposal so unrelated decisions from the prior round are not lost. The existing-file read
informs context only; when it conflicts with the user feedback in the prompt, the user feedback
wins. The prior draft may be out of sync with the latest feedback — for example, if an earlier round
returned Readiness Issues without overwriting the file.

### Step 2: Readiness Check

Check for blockers. Push back if any of:

- **Questions**: Unresolved `[ ]` items in `### Questions` that would affect scoping
- **Unvalidated assumptions**: `[ ]` items in `### Assumptions` that carry risk
- **Insufficient approach**: Approach is missing, placeholder, or too vague to scope a phase from
- **Ambiguous ACs**: ACs that can't be decomposed into concrete tasks

If blockers found, return:

```
## Result: Readiness Issues

1. [issue description] — suggested resolution
2. ...
```

If no blockers, proceed to Step 3.

### Step 3: Propose Phase

If after reviewing all ACs, Approach, Research, and prior phases there is no coherent work to scope
— no tasks that serve ACs, no cleanup justified by prior phases, no direction from Approach or
Research — return:

```
## Result: No Work Remaining
No phase to scope.
```

Otherwise, scope the next slice of work:

- Review all ACs (any marker), Approach, Research, and prior phases to identify what to work on
- Name the phase to reflect its scope
- Write a brief approach summary (strategy, constraints, patterns)
- Compose tasks. For each task, map it to existing ACs regardless of marker:
  - `(ACN, satisfy)` — task directly implements an AC that is not yet satisfied
  - `(ACN, enhance)` — task improves or refines an already-satisfied AC
  - No annotation — task is pure implementation detail (cleanup, refactoring, tooling)
- Only propose a new AC when a task represents a genuinely new spec-level condition that existing
  ACs don't cover. An AC describes a desired end state or behavior of the finished system; a task
  describes an implementation step that reaches it. If the candidate reads as a step, it is a task,
  not an AC.

### Step 4: Write Phase File

Write the phase file at the absolute path provided by the orchestrator using the New Phase template:

```markdown
## Phase P: Phase Name

### Context

[Brief summary of what this phase addresses and why]

### Approach

[Strategy and architectural notes]

### Tasks
1. [ ] [task description] (AC1, satisfy)
2. [ ] [task description] (AC2, enhance)
3. [ ] [cleanup or refactoring task]

### Issues
```

Use the `P` value from the orchestrator's inputs in the `## Phase P: Phase Name` header. If a file
already exists at the provided path (from a prior refinement round), overwrite it.

### Step 5: Return Result

Return one of:

```
## Result: No Work Remaining
No phase to scope.
```

```
## Result: Phase Proposal

**Name**: [phase name]
**Targeted ACs**: [list of AC numbers]
**Written**: [absolute path to the phase file written in Step 4]
```

(The `## Result: Readiness Issues` format is in Step 2.)

## Rules

- Write only the phase file at the provided path. Never modify `00-main.md` or any earlier phase's
  file in the objective (phases with a number other than the `P` provided in the prompt). The
  provided path itself may be overwritten on refinement rounds — see Step 4.
- Tasks should be atomic: one clear outcome each
- Prefer codify-before-satisfy when practical (TDD)
- AC annotations: `(ACN, satisfy)` for implementing a not-yet-satisfied AC, `(ACN, enhance)` for
  refining an already-satisfied AC, no annotation for implementation detail
- Phase scoping is just-in-time: one phase at a time, informed by remaining ACs and prior learnings
- AC changes require human approval — flag in readiness issues, do not modify
- **Phase atomicity**: A phase must contain only interdependent tasks — tasks that must land
  together for the change to make sense. If a task could be committed independently without breaking
  the others, it belongs in a separate phase. Example: "add helper function" and "update caller to
  use helper" are interdependent (one phase). "Add helper function" and "rename unrelated config
  key" are independent (two phases).
- **"And" self-check**: If the phase description needs "and" to connect independent actions, split
  into separate phases. "Add atomicity rules to scope brief" is one action. "Add atomicity rules to
  scope brief and fix review dispatch bug" is two independent actions — two phases.
