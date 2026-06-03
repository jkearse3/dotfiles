# Phase Scope Brief

Read the objective at `.objectives/_current/00-main.md` and propose the next phase. On a valid
proposal, write the phase file at the absolute path provided by the orchestrator.

## Arguments

The orchestrator provides these inputs in the prompt:

- `objective_dir` — absolute path to the active objective directory
- `P` — next phase number (matches the `## Phases` index entry)
- `NN` — next sequence number for the phase filename
- `Phase file` — absolute path to the phase file to write (i.e., `<objective_dir>/NN-phase-P.md`)

## References

- `references/contracts.md` — file conventions and invariants (single-revision rule, caller-token
  preservation).
- `references/phases.md` — phase resolution (linked file vs. inline `## Phase N:` section).

## Write Permissions

- Write the phase file at the provided path (create, overwrite on refinement rounds)

## Steps

1. Read state. From `00-main.md`, read:
   - `## Acceptance Criteria` — all ACs and their markers.
   - `## Approach` — implementation roadmap.
   - `## Research` — findings, decisions, questions, assumptions.
   - `## Phases` index — apply Phase Resolution to each phase (read the linked file if the index
     entry has a markdown link; otherwise read the inline `## Phase N:` section). Review prior
     learnings, completed task patterns, and issues encountered.
   - If a file already exists at the provided phase-file path, read it — this is a refinement round
     holding the prior draft's approach and tasks. Carry that context forward so unrelated prior
     decisions are not lost. The existing-file read informs context only; when it conflicts with the
     user feedback in the prompt, the feedback wins. The prior draft may be out of sync with the
     latest feedback (e.g., an earlier round returned Readiness Issues without overwriting the
     file).

2. Readiness check. Push back if any blocker applies:
   - **Questions**: unresolved `[ ]` items in `### Questions` that would affect scoping.
   - **Unvalidated assumptions**: `[ ]` items in `### Assumptions` that carry risk.
   - **Insufficient approach**: approach is missing, placeholder, or too vague to scope from.
   - **Ambiguous ACs**: ACs that can't be decomposed into concrete tasks.

   If blockers found, return the `## Result: Readiness Issues` block (see Contracts) and stop.
   Otherwise proceed.

3. Propose phase. If after reviewing all ACs, Approach, Research, and prior phases there is no
   coherent work to scope — no tasks that serve ACs, no cleanup justified by prior phases, no
   direction from Approach or Research — return the `## Result: No Work Remaining` block and stop.

   Otherwise, scope the next slice of work:
   - Review all ACs (any marker), Approach, Research, and prior phases to identify what to work on.
   - Name the phase to reflect its scope.
   - Write a brief approach summary (strategy, constraints, patterns).
   - Compose tasks. Map each task to existing ACs regardless of marker:
     - `(ACN, satisfy)` — task directly implements an AC that is not yet satisfied.
     - `(ACN, enhance)` — task improves or refines an already-satisfied AC.
     - No annotation — task is pure implementation detail (cleanup, refactoring, tooling).
   - Only propose a new AC when a task represents a genuinely new spec-level condition that existing
     ACs don't cover. An AC describes a desired end state or behavior of the finished system; a task
     describes an implementation step that reaches it. If the candidate reads as a step, it is a
     task, not an AC.

4. Write phase file. Write at the absolute path provided by the orchestrator using the New Phase
   template (see Contracts). Use the `P` value in the `## Phase P: Phase Name` header. Include only
   required sections unless optional phase-local sections from `references/phases.md` already have
   content to preserve from a refinement round. If a file already exists at the provided path (prior
   refinement round), overwrite it.

5. Return result. Return one `## Result:` block (see Contracts): `Phase Proposal` on success,
   `No Work Remaining` if nothing to scope, or `Readiness Issues` if Step 2 found blockers.

## Contracts

### Result Blocks

Return exactly one. Headings and fields are caller-parsed — do not rename or reorder.

```
## Result: Readiness Issues

1. [issue description] — suggested resolution
2. ...
```

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

### New Phase Template

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

### AC Annotations

- `(ACN, satisfy)` — implement a not-yet-satisfied AC.
- `(ACN, enhance)` — refine an already-satisfied AC.
- No annotation — implementation detail.

### Write Boundary

- Write only the phase file at the provided path. Never modify `00-main.md` or any earlier phase's
  file (phases numbered other than the provided `P`). The provided path itself may be overwritten on
  refinement rounds — see Step 4.
- AC changes require human approval — flag in readiness issues, do not modify.

### Scoping Rules

- Tasks should be atomic: one clear outcome each.
- Prefer codify-before-satisfy when practical (TDD).
- Phase scoping is just-in-time: one phase at a time, informed by remaining ACs and prior learnings.
- Do not add empty optional sections to new phases. Add `### Decisions` or `### Continuation` only
  when the phase has phase-local content for that section.
- **Phase atomicity**: a phase must contain only interdependent tasks — tasks that must land
  together for the change to make sense. If a task could be committed independently without breaking
  the others, it belongs in a separate phase. Example: "add helper function" and "update caller to
  use helper" are interdependent (one phase). "Add helper function" and "rename unrelated config
  key" are independent (two phases).
- **"And" self-check**: if the phase description needs "and" to connect independent actions, split
  into separate phases. "Add atomicity rules to scope brief" is one action. "Add atomicity rules to
  scope brief and fix review dispatch bug" is two independent actions — two phases.
