# Spec

Define acceptance criteria at objective level and validate they're achievable.

ACs live in `00-main.md` under `## Acceptance Criteria`. Phase sections reference ACs by number.

## Arguments

Optional topic to scope interrogation. When provided, interrogation focuses on the topic and new ACs
are appended to the existing list. When omitted, use focused phase continuation when it has status
`SPEC_CHANGE_REQUIRED`; otherwise use full re-review behavior.

## References

- `references/contracts.md` — § Load Current Objective for the load/nudge gate; § Continuation
  Lifecycle; § Invariants for approval gates and AC semantics.
- `references/phases.md` — Phase Resolution for locating focused phase continuation.
- `references/spec-definition.md` — § Spec Definition for interrogation, scenario cross-check, and
  AC drafting.
- `references/acceptance-criteria.md` — AC precision rules, stability/locking semantics, and the
  `[-]` invalidation format that govern conflict checks.
- `references/index-format.md` — AC numbering and marker format consumed when writing
  `## Acceptance Criteria`.

## Steps

1. Load objective. Read `.objectives/_current/00-main.md` per `references/contracts.md` § Load
   Current Objective, including its no-objective nudge. If a focused phase exists, resolve its
   content per `references/phases.md` § Phase Resolution and read `### Continuation` when present.

2. Review research. Read the Research section in `00-main.md`:
   - What do we know?
   - What constraints exist?
   - Are there unresolved questions blocking AC definition?
   - If critical gaps: suggest `/objective investigate` first.

3. Interrogate requirements. Apply `references/spec-definition.md` § Spec Definition. If no topic
   argument was provided and the focused phase contains `### Continuation` with
   `Status: SPEC_CHANGE_REQUIRED`, use its Summary, Route, Clear when, and any Payload as the
   default spec-change topic and context.

4. Scenario cross-check. Apply `references/spec-definition.md` § Spec Definition before defining
   ACs, using topic mode for an explicit topic or `SPEC_CHANGE_REQUIRED` default context and full
   mode otherwise.

5. Define ACs. Draft objective ACs from validated answers and included scenarios per
   `references/spec-definition.md` § Spec Definition.

6. Conflict check (topic mode only — skip in full mode). Using the drafted ACs from Step 5, apply
   `references/acceptance-criteria.md` § AC Conflict Check before writing. The drafted ACs are the
   new AC candidates, after any topic-mode deduplication against existing coverage. Preserve the
   approval gate: conflict analysis and drafted ACs require user approval before writing
   `## Acceptance Criteria` in `00-main.md`.

7. Validate achievability. For each active AC (skip `[-]`), verify:
   - Technical feasibility given research findings.
   - No blockers in questions/assumptions.
   - Dependencies can be satisfied.
   - Document validation findings in Research > Findings.

8. Define approach. After ACs are stable, define the `## Approach` section.

   Topic mode: re-derive the approach to incorporate all active ACs (existing + new, excluding `[-]`
   invalidated). The approach is holistic — it must account for the full set of active ACs, not just
   the new ones.

   Full mode: define the approach from scratch.

   Interrogate for:
   - **Sequencing**: What must happen first? What can be parallelized? What depends on what?
   - **Constraints**: Architectural boundaries, patterns to follow/avoid, performance budgets.
   - **Strategy**: High-level how — which components change, what patterns to use, key design
     decisions.

   The approach must be detailed enough that an agent can scope phases and execute without further
   user input. If the user's answers are vague, push for specifics. Write to `## Approach` in
   `00-main.md`.

9. Clear or update continuation. After approved AC, Approach, and validation-finding writes are
   persisted to `00-main.md`, apply `references/contracts.md` § Continuation Lifecycle for
   `Status: SPEC_CHANGE_REQUIRED`.

10. Present summary:
    - List ACs with status (including any invalidated ACs with cross-references).
    - Approach summary.
    - Validation concerns (if any).
    - Continuation cleared or updated, including the next resume route when applicable.
    - Suggest next: refine ACs/approach, more research, or ready for `/objective phase-iterate`.

## Contracts

- Writes to `00-main.md`: `## Acceptance Criteria`, `## Approach`, and validation findings under
  `## Research > ### Findings`. Writes to the focused phase file: `### Continuation`, per
  `references/contracts.md` § Continuation Lifecycle.
- Preserve verbatim: the five interrogation dimensions and their sub-questions, the scenario
  cross-check categories and skip condition, the AC-definition rules, and the shared conflict-check
  approval gate plus markers/invalidation format.
- Structured questions follow `references/spec-definition.md` § Spec Definition structured-question
  behavior.
- ACs are the contract — changes require user approval. Conflict check (Step 6) is an approval gate,
  not an automatic write.
- Focused phase `### Continuation` with `Status: SPEC_CHANGE_REQUIRED` is the default spec-change
  topic and context when no explicit topic argument is provided.
- Re-spec means re-review (full mode only): existing ACs aren't sacred — assess completeness against
  all dimensions every time.
- Interrogate aggressively (ask all relevant questions upfront), iterate until clear (if answers
  reveal new questions, ask them before defining ACs), and pre-fill, don't assume silently (state
  obvious answers as pre-filled assumptions for validation; only ask open-ended questions for
  genuinely ambiguous dimensions).
- User drives the outer loop: research ↔ spec until confident.
- Don't define tasks here — tasks are scoped by `/objective phase-scope`.
- Mark `(human)` for subjective criteria (UX, feel, etc.).
