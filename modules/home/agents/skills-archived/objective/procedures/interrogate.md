# Interrogate

Invoke the `interrogate` skill and merge deliberative decisions into the
objective. The skill interviews the user; this procedure handles persistence.

## Arguments

Optional topic to interrogate. If omitted, derive from focused phase
continuation when it has status `NEEDS_DECISION` with `Scope: objective`;
otherwise derive from objective context or conversation history.

## References

- `references/current-objective.md` — § Load Current Objective for the active
  objective gate.
- `references/workflow-invariants.md` — § Continuation Lifecycle and §
  Invariants.
- `references/objective-index-format.md` — `00-main.md` section layout.

## Steps

1. Load objective. Read `.objectives/_current/00-main.md`. If a focused phase
   exists, read `references/phase-index.md` and resolve its content per § Phase
   Resolution, then read `### Continuation` when present.
   - If an objective exists: go to Step 2.
   - If no objective: stop with the nudge from `references/current-objective.md`
     § Load Current Objective.

2. Derive topic. If no topic argument was provided:
   - If a focused phase exists and contains `### Continuation` with
     `Status: NEEDS_DECISION` and objective scope in its Payload or Route, use
     its Summary, Route, Clear when, and any Payload as the default
     interrogation topic and context.
   - Otherwise, read `## Research > ### Questions`, `## Context`, then
     `## Approach` from `00-main.md` (in order), then synthesize a focused
     interrogate topic from the first section with unresolved items:
     - `## Research > ### Questions`: unanswered questions drive deliberation.
     - `## Context`: stated motivation and background.
     - `## Approach`: proposed strategy and architecture.
   - If no objective content provides direction, derive the topic from the
     conversation history.
   - If nothing is available, stop: "No questions or context to interrogate.
     Provide a topic or add questions first."

3. Invoke the interrogate skill via the Skill tool with the topic from Step 2.
   The skill walks through decisions one at a time, recording resolved and
   outstanding choices. It is not aware of objectives. Wait for the session to
   complete, capturing the full decisions log.

4. Merge decisions into `## Research > ### Decisions` in `00-main.md`:
   - Append resolved decisions (choices with rationale) as `[x]` items.
   - Append decisions deferred or surfaced during interrogation as `[ ]` items.
   - Dedupe against existing `### Decisions` items by content match — skip any
     that already appear.
   - Do not overwrite or remove existing decisions.
   - Merge decisions only — no findings, questions, or assumptions (unlike
     `/investigate`).

5. Clear or update continuation. After Step 4 has persisted objective-wide
   decisions to `00-main.md`, apply `references/workflow-invariants.md` §
   Continuation Lifecycle for `Status: NEEDS_DECISION` with objective scope.

6. Present summary.
   - Key decisions made this session.
   - Open decisions requiring future resolution.
   - New questions that surfaced during interrogation.
   - Continuation cleared or updated, including the next resume route when
     applicable.
   - Suggest next: more interrogation, or ready for `/objective spec`.

## Contracts

- Writes `## Research > ### Decisions` in `00-main.md`. Writes to the focused
  phase file: `### Continuation`, per `references/workflow-invariants.md` §
  Continuation Lifecycle.
- Preserve the no-objective nudge, the topic-derivation fallback, and the
  decisions-merge semantics verbatim.
- The interrogate skill is interactive and objective-unaware — all persistence
  happens in Step 4.
- Run `/objective interrogate` again per topic for separate sessions; the
  objective accumulates state, so nothing is lost between runs.
- Decisions inform Spec and Approach. Do not define ACs here.
- Focused phase `### Continuation` with `Status: NEEDS_DECISION` and objective
  scope is the default topic and context when no explicit topic argument is
  provided.
