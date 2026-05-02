# Phase Scope Brief

## Instructions

Read the goal at `.goals/_current/00-main.md` and propose the next phase. On a valid proposal, write
the phase file at the absolute path provided by the orchestrator.

### Step 1: Read State

The orchestrator provides the following inputs in the prompt:

- `goal_dir` — absolute path to the active goal directory
- `P` — next phase number (matches the `## Phases` index entry)
- `NN` — next sequence number for the phase filename
- `Phase file` — absolute path to the phase file to write (i.e., `<goal_dir>/NN-phase-P.md`)

Read these sections from `00-main.md`:

- `## Acceptance Criteria` — identify remaining `[ ]` ACs
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

If no remaining `[ ]` ACs exist, return:

```
## Result: No Work Remaining
All ACs satisfied. No phase to scope.
```

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

Scope the next slice of work:

- Select which `[ ]` ACs to target (prefer small, coherent slices)
- Name the phase to reflect its scope
- Write a brief approach summary (strategy, constraints, patterns)
- Compose an initial task list with AC references

### Step 4: Write Phase File

Write the phase file at the absolute path provided by the orchestrator using the New Phase template:

```markdown
## Phase P: Phase Name

### Context

[Brief summary of what this phase addresses and why]

### Approach

[Strategy and architectural notes]

### Tasks
1. [ ] [task description] (ACN, satisfy)
2. [ ] [task description] (ACM, satisfy)

### Issues
```

Use the `P` value from the orchestrator's inputs in the `## Phase P: Phase Name` header. If a file
already exists at the provided path (from a prior refinement round), overwrite it.

### Step 5: Return Result

Return:

```
## Result: Phase Proposal

**Name**: [phase name]
**Targeted ACs**: [list of AC numbers]
**Written**: [absolute path to the phase file written in Step 4]
```

## Rules

- Write only the phase file at the provided path. Never modify `00-main.md` or any earlier phase's
  file in the goal (phases with a number other than the `P` provided in the prompt). The provided
  path itself may be overwritten on refinement rounds — see Step 4.
- Tasks should be atomic: one clear outcome each
- Prefer codify-before-satisfy when practical (TDD)
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
