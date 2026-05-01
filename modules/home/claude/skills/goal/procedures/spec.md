# Spec

Define acceptance criteria at goal level and validate they're achievable.

ACs live in `00-main.md` under `## Acceptance Criteria`. Phase sections reference ACs by number.

Read these format references before executing this procedure:

- `${CLAUDE_SKILL_DIR}/references/acceptance-criteria.md`
- `${CLAUDE_SKILL_DIR}/references/index-format.md`

## Arguments

Optional topic to scope interrogation. When provided, interrogation focuses on the topic and new ACs
are appended to the existing list. When omitted, full re-review behavior.

## Steps

1. **Load goal**: Read `.goals/_current/00-main.md`
   - If no goal: nudge — "No active goal. Want me to load or create one?"

2. **Review research**: Read Research section in `00-main.md`
   - What do we know?
   - What constraints exist?
   - Are there unresolved questions blocking AC definition?
   - If critical gaps: suggest `/goal research` first

3. **Interrogate requirements**: Use AskUserQuestion tool for clarifying questions.

   **If topic argument provided** (topic mode):

   Interrogation is scoped to the topic. Only assess dimensions relevant to the new scope — skip
   dimensions already fully covered by existing ACs unless the topic introduces new concerns.
   - Read existing ACs to understand current coverage
   - Focus on what the topic adds or changes: new behavior, new constraints, new edge cases
   - Pre-fill aggressively from context, research, and existing ACs — the topic narrows the search
     space
   - Ask only about genuinely ambiguous aspects of the topic
   - Iterate until the topic's scope is clear

   **If no topic argument** (full mode):

   **Proportional investigation**: Check all 5 dimensions, but pre-fill obvious answers from context
   and research. Only ask about genuinely ambiguous dimensions. For trivial changes, most dimensions
   have obvious answers — present them for quick validation instead of open-ended questions.

   **If ACs already exist**:
   - Review current ACs against all dimensions below
   - Assess: Are any dimensions uncovered? Any ACs vague or incomplete?
   - Present current ACs with gap analysis
   - Ask clarifying questions for any gaps found
   - Continue until all dimensions addressed

   **If no ACs exist**: Assess all dimensions, pre-filling what's obvious:

   **Objective & Scope**:
   - What problem are we solving? What does success look like?
   - What's explicitly in scope? Out of scope?
   - What would make this "done" vs "good enough"?
   - What would make this incomplete or fail to solve the problem?

   **Constraints & Dependencies**:
   - Performance requirements? (latency, throughput, memory)
   - Compatibility requirements? (versions, browsers, platforms)
   - What depends on this? What does this depend on?
   - What happens when these constraints are violated or unmet?

   **Users & Behavior**:
   - Who uses this? What do they expect?
   - Edge cases: empty, null, boundary, error states?
   - What happens when things go wrong?
   - What error messages, fallbacks, or degraded states are needed?

   **Architecture & Patterns**:
   - How does this fit existing system?
   - What patterns should we follow/avoid?
   - Security considerations? Trust boundaries?
   - What breaks if dependencies change, drift, or become unavailable?

   **Verification**:
   - How will we know each criterion is met?
   - What's testable automatically vs needs human judgment?
   - What would a regression look like?
   - What failure modes should tests guard against?

   For each dimension: if the answer is obvious from context, state it as a pre-filled assumption
   for the user to confirm or correct. Only ask open-ended questions for genuinely ambiguous
   dimensions. Present pre-filled answers and questions together, wait for validation. Iterate until
   no ambiguity remains.

4. **Scenario cross-check**: Systematically enumerate edge-case scenarios before defining ACs.

   **Skip condition**: For trivial changes where interrogation required minimal clarification, skip
   this step — the proportional investigation model applies here too. If most dimensions had obvious
   pre-filled answers, the change is unlikely to have hidden edge cases.

   **Category checklist** — for each category, enumerate applicable scenarios from the dimension
   answers:
   - **Absence**: empty, null, missing, zero-length, omitted values
   - **Boundaries**: min, max, overflow, truncation, off-by-one
   - **Invalid input**: malformed data, wrong types, unexpected formats
   - **Dependencies**: cross-references, external contracts, upstream/downstream consumers
   - **State & ordering**: transitions, sequencing, concurrency, partial completion
   - **Degradation**: failure modes, fallbacks, error messages, partial success

   **Topic mode**: Scope the cross-check to the topic's domain. Only walk categories relevant to
   what the topic introduces or changes. Check candidate scenarios against existing ACs to avoid
   duplication.

   **Full mode**: Walk all categories against the full set of dimension answers.

   **Process**:
   1. For each category, derive concrete scenarios from the interrogation answers
   2. Apply precision rules from the format reference to each candidate — it must state what happens
      (not what doesn't), include concrete values where applicable, and describe an observable
      outcome
   3. Discard vague candidates that can't be made precise
   4. Present surviving scenarios to the user as candidates for inclusion as ACs
   5. User includes or excludes each candidate before proceeding to AC definition

5. **Define ACs**: From answers and included scenarios, establish acceptance criteria.

   **Topic mode** (topic argument provided) — draft only, do not write yet:
   - Draft new ACs starting at the next number after the highest existing AC
   - Do not rewrite or renumber existing ACs
   - Each new AC should map to answers from the topic-scoped interrogation
   - Proceed to conflict check (step 6) before presenting or writing

   **Full mode** (no topic argument):
   - Clear, verifiable conditions for "done"
   - Number ACs for task references
   - Each AC should map to a specific answer from interrogation

   **Both modes**:
   - Apply precision rules from the format reference — state what happens (not what doesn't),
     include concrete values, describe observable outcomes
   - Mark `(human)` for criteria requiring user sign-off

6. **Conflict check** (topic mode only — skip in full mode):

   Using the drafted ACs from step 5, scan existing ACs for conflicts before writing:
   - For each existing AC, check if any new AC contradicts, overlaps with, or supersedes it
   - **Unlocked ACs** (marker is `[ ]` and no task references `(ACN, ...)`): update in place
   - **Locked ACs** (marker is not `[ ]`, or task references exist): invalidate using `[-]` +
     strikethrough + cross-reference per AC stability rules in the format reference

   Present the conflict analysis to the user: which ACs will be updated, which invalidated, and what
   new ACs will be added. Require user approval before writing.

   If no conflicts: present drafted ACs for user approval.

   After approval, write all ACs (existing + new, with any updates/invalidations applied) to
   `## Acceptance Criteria` in `00-main.md`.

7. **Validate achievability**: For each AC (active ones only, skip `[-]`), verify:
   - Technical feasibility given research findings
   - No blockers in questions/assumptions
   - Dependencies can be satisfied
   - Document validation findings in Research > Findings

8. **Define approach**: After ACs are stable, define the `## Approach` section.

   **Topic mode**: Re-derive the approach to incorporate all active ACs (existing + new, excluding
   `[-]` invalidated). The approach is holistic — it must account for the full set of active ACs,
   not just the new ones.

   **Full mode**: Define approach from scratch.

   Interrogate for:
   - **Sequencing**: What must happen first? What can be parallelized? What depends on what?
   - **Constraints**: Architectural boundaries, patterns to follow/avoid, performance budgets
   - **Strategy**: High-level how — which components change, what patterns to use, key design
     decisions

   The approach must be detailed enough that an agent can scope phases and execute without further
   user input. If the user's answers are vague, push for specifics.

   Write to `## Approach` in `00-main.md`.

9. **Present summary**:
   - List ACs with status (including any invalidated ACs with cross-references)
   - Approach summary
   - Validation concerns (if any)
   - Suggest next: refine ACs/approach, more research, or ready for `/goal phase-iterate`

## Outputs

Writes to `00-main.md`:

- `## Acceptance Criteria`
- `## Approach`
- `## Research > ### Findings` (validation findings)

## Notes

- **Use AskUserQuestion**: All clarifying questions must go through the tool — don't just list
  questions in text
- **Re-spec means re-review** (full mode only): Existing ACs aren't sacred — assess completeness
  against all dimensions every time
- **Interrogate aggressively**: Ask all relevant questions upfront, batch by dimension
- **Iterate until clear**: If answers reveal new questions, ask them before defining ACs
- **Pre-fill, don't assume silently**: State obvious answers as pre-filled assumptions for user
  validation. Only ask open-ended questions for genuinely ambiguous dimensions.
- ACs are the contract — changes require user approval
- User drives outer loop: research ↔ spec until confident
- Don't define tasks here — tasks are scoped by `/goal phase-scope`
- Mark `(human)` for subjective criteria (UX, feel, etc.)
