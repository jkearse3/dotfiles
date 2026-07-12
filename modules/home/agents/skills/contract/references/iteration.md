# Contract Iteration

Iteration realizes the contract through coherent revisions while acceptance criteria remain the
authority for completion. ACs and revisions are many-to-many: one behavior change may advance
several ACs, and one AC may require several revisions.

## Slice Selection

Choose the next independently verifiable state transition that advances unsatisfied or partial ACs.
Prefer prerequisite behavior first and one primary review question. Slice by behavior and risk, not
file, layer, task count, estimated size, or AC count.

Before editing, state this ephemeral boundary:

```markdown
Target ACs: <numbers>

Base: <intended base revision or bookmark>

Intended transition:
<One coherent behavior or repository-state change.>

Review question:
<The primary question this revision should answer.>

Preserves:
- <Relevant behavior or invariant.>

Stop before:
- <Adjacent behavior, ambiguity, or agreement change.>

Verification:
- <Focused command or inspection.>
```

Do not persist this boundary in the contract or another workflow file. Its durable result is the
finalized diff and revision description.

## Autonomous Decisions

Iteration may autonomously change implementation details, slice boundaries, and remaining order when
the approved behavior, boundaries, checks, and compatibility constraints remain unchanged. It may
adjust the slice when implementation evidence shows that another coherent boundary advances the same
agreement more safely. Applicable rules determine revision shaping, verification, review, fixes, and
bookmark handling.

Reconciliation may update only measured state: AC markers, `Evidence:` lines, `Status:`, and
directly verified research question or assumption status. Changing AC wording or checks, the spec,
boundaries, implementation constraints, validation requirements, or intended externally visible
behavior requires the amendment procedure and explicit approval.

## Stop Conditions

Stop iteration when:

- Every non-superseded AC is satisfied with evidence.
- A user decision, missing prerequisite, or unsafe ambiguity blocks progress.
- Correct work requires changing the agreement or crossing a forbidden or stop-before boundary.
- Required verification cannot be performed safely or its result contradicts the contract.
- Unrelated or ambiguously owned work conflicts with the selected slice.
- The intended base, bookmark stack, rewrite ownership, or publication boundary is ambiguous.
- A review finding crosses agreement, ownership, or revision boundaries.
- Repeated attempts fail without producing new evidence, or context pressure makes continuation
  unsafe.

Do not stop merely because implementation differs from non-binding guidance, a slice needs safe
replanning, or a coherent revision advances more ACs than expected.
