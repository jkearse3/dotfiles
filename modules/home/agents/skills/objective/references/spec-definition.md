# Spec Definition

Reusable spec-definition behavior for drafting objective-level acceptance criteria.

## Spec Definition

Use this operation when drafting objective-level ACs from research, user answers, and scenario
cross-checks.

Apply proportional interrogation:

- Use the agent's structured question mechanism for all clarifying questions when available;
  otherwise ask the question in text and stop until the user answers. Batch related questions in one
  structured prompt or call when using a structured mechanism.
- If an answer is obvious from context, research, or existing ACs, state it as a pre-filled
  assumption for the user to confirm or correct.
- Ask open-ended questions only for genuinely ambiguous dimensions.
- Present pre-filled answers and questions together, wait for validation, and iterate until no
  ambiguity remains.

Modes:

- Topic mode: when a topic argument is provided, or when the caller defaults from a
  `SPEC_CHANGE_REQUIRED` continuation, scope interrogation to the topic. Read existing ACs, focus on
  what the topic adds or changes, skip dimensions already fully covered unless the topic introduces
  new concerns, pre-fill aggressively, and ask only about ambiguous topic details.
- Full mode: when there is no topic and no `SPEC_CHANGE_REQUIRED` continuation, re-review the whole
  objective. Check all five dimensions, pre-fill obvious answers, present current ACs with gap
  analysis when ACs already exist, and continue until all dimensions are addressed.

Dimensions:

- **Objective & Scope**: What problem are we solving? What does success look like? What's explicitly
  in scope / out of scope? What makes this "done" vs "good enough"? What would make it incomplete or
  fail to solve the problem?
- **Constraints & Dependencies**: Performance requirements (latency, throughput, memory)?
  Compatibility requirements (versions, browsers, platforms)? What depends on this and what does
  this depend on? What happens when these constraints are violated or unmet?
- **Users & Behavior**: Who uses this and what do they expect? Edge cases — empty, null, boundary,
  error states? What happens when things go wrong? What error messages, fallbacks, or degraded
  states are needed?
- **Architecture & Patterns**: How does this fit the existing system? What patterns should we follow
  or avoid? Security considerations and trust boundaries? What breaks if dependencies change, drift,
  or become unavailable?
- **Verification**: How will we know each criterion is met? What's testable automatically vs needs
  human judgment? What would a regression look like? What failure modes should tests guard against?

Apply scenario cross-check before defining ACs:

- Skip condition: for trivial changes where interrogation required minimal clarification, skip the
  cross-check. The proportional investigation model applies here too. If most dimensions had obvious
  pre-filled answers, the change is unlikely to have hidden edge cases.
- Topic mode: scope the cross-check to the topic's domain, including any caller-provided default
  topic/context. Only walk categories relevant to what the topic introduces or changes. Check
  candidate scenarios against existing ACs to avoid duplication.
- Full mode: walk all categories against the full set of dimension answers.

Scenario categories:

- **Absence**: empty, null, missing, zero-length, omitted values.
- **Boundaries**: min, max, overflow, truncation, off-by-one.
- **Invalid input**: malformed data, wrong types, unexpected formats.
- **Dependencies**: cross-references, external contracts, upstream/downstream consumers.
- **State & ordering**: transitions, sequencing, concurrency, partial completion.
- **Degradation**: failure modes, fallbacks, error messages, partial success.

For each applicable category, derive concrete scenarios from interrogation answers, apply the
precision rules from `references/ac-precision.md`, discard vague candidates, present surviving
scenarios to the user as AC candidates, and have the user include or exclude each candidate before
AC definition.

Draft ACs from validated answers and included scenarios:

- Topic mode: draft only. Start at the next number after the highest existing AC, do not rewrite or
  renumber existing ACs, map each new AC to the topic-scoped interrogation, deduplicate against
  existing coverage, then run `references/ac-conflict-check.md` § AC Conflict Check before
  presenting or writing.
- Full mode: define clear, verifiable conditions for "done", number ACs for task references, and map
  each AC to a specific answer from interrogation.
- Both modes: apply the precision rules from `references/ac-precision.md` — declare a state or
  behavior, not a step; state what happens, not what doesn't; include concrete values where
  applicable; describe observable outcomes.
- Mark `(human)` for criteria requiring user sign-off, including subjective criteria such as UX or
  feel.
