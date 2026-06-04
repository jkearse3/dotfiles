# Interrogate

Invoke the `interrogate` skill and merge deliberative decisions into the objective. The skill
interviews the user; this procedure handles persistence.

## Arguments

Optional topic to interrogate. If omitted, derive from focused phase continuation when it has status
`NEEDS_DECISION` with `Scope: objective`; otherwise derive from objective context or conversation
history.

## References

- `references/contracts.md` — file conventions, invariants, and Continuation Lifecycle.
- `references/index-format.md` — `00-main.md` section layout and marker semantics.
- `references/phases.md` — Phase Resolution for locating focused phase continuation.
- `references/structure.md` — objective registry and symlink layout.

## Steps

1. Load objective. Read `.objectives/_current/00-main.md`. If a focused phase exists, resolve its
   content per `references/phases.md` § Phase Resolution and read `### Continuation` when present.
   - If an objective exists: go to Step 2.
   - If no objective: run the auto-creation flow below, then go to Step 2.

   Auto-creation flow (no active objective): apply `references/contracts.md` § Spike Auto-Creation
   with these caller parameters:
   - Spike kind: `decision spike`.
   - Require-topic nudge: "No active objective. Provide a topic to start a decision spike, or want
     me to load/create an objective?"
   - Slug example: "what database should we use for the new service" → `database-decision`.
   - Confirmation example: "Starting decision spike. Branch and objective will be named
     `database-decision`. Proceed, or provide an alternative name?"
   - Create argument: confirmed slug.

2. Derive topic. If no topic argument was provided:
   - If a focused phase exists and contains `### Continuation` with `Status: NEEDS_DECISION` and
     objective scope in its Payload or Route, use its Summary, Route, Clear when, and any Payload as
     the default interrogation topic and context.
   - Otherwise, read `## Research > ### Questions`, `## Context`, then `## Approach` from
     `00-main.md` (in order), then synthesize a focused interrogate topic from the first section
     with unresolved items:
     - `## Research > ### Questions`: unanswered questions drive deliberation.
     - `## Context`: stated motivation and background.
     - `## Approach`: proposed strategy and architecture.
   - If no objective content provides direction, derive the topic from the conversation history.
   - If nothing is available, stop: "No questions or context to interrogate. Provide a topic or add
     questions first."

3. Invoke the interrogate skill via the Skill tool with the topic from Step 2. The skill walks
   through decisions one at a time, recording resolved and outstanding choices. It is not aware of
   objectives. Wait for the session to complete, capturing the full decisions log.

4. Merge decisions into `## Research > ### Decisions` in `00-main.md`:
   - Append resolved decisions (choices with rationale) as `[x]` items.
   - Append decisions deferred or surfaced during interrogation as `[ ]` items.
   - Dedupe against existing `### Decisions` items by content match — skip any that already appear.
   - Do not overwrite or remove existing decisions.
   - Merge decisions only — no findings, questions, or assumptions (unlike `/investigate`).

5. Clear or update continuation. After Step 4 has persisted objective-wide decisions to
   `00-main.md`, apply `references/contracts.md` § Continuation Lifecycle for
   `Status: NEEDS_DECISION` with objective scope.

6. Present summary.
   - Key decisions made this session.
   - Open decisions requiring future resolution.
   - New questions that surfaced during interrogation.
   - Continuation cleared or updated, including the next resume route when applicable.
   - Suggest next: more interrogation, or ready for `/objective spec`.

## Contracts

- Writes `## Research > ### Decisions` in `00-main.md`. Writes to the focused phase file (or inline
  phase section): `### Continuation`, per `references/contracts.md` § Continuation Lifecycle.
- Preserve the auto-creation nudge, the topic-derivation fallback, and the decisions-merge semantics
  verbatim.
- The interrogate skill is interactive and objective-unaware — all persistence happens in Step 4.
- Run `/objective interrogate` again per topic for separate sessions; the objective accumulates
  state, so nothing is lost between runs.
- Decisions inform Spec and Approach. Do not define ACs here.
- Focused phase `### Continuation` with `Status: NEEDS_DECISION` and objective scope is the default
  topic and context when no explicit topic argument is provided.
