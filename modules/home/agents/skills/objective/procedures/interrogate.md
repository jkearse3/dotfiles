# Interrogate

Invoke the `interrogate` skill and merge deliberative decisions into the objective. The skill
interviews the user; this procedure handles persistence.

## Arguments

Optional topic to interrogate. If omitted, derive from objective context or conversation history.

## References

- `references/contracts.md` — file conventions and invariants.
- `references/index-format.md` — `00-main.md` section layout and marker semantics.
- `references/structure.md` — objective registry and symlink layout.

## Steps

1. Load objective. Read `.objectives/_current/00-main.md`.
   - If an objective exists: go to Step 2.
   - If no objective: run the auto-creation flow below, then go to Step 2.

   Auto-creation flow (no active objective):
   1. Require topic. If no topic argument was provided, nudge and stop: "No active objective.
      Provide a topic to start a decision spike, or want me to load/create an objective?"
   2. Extract slug. From the topic, take 2-3 key terms forming a compact, descriptive slug
      (lowercase, hyphen-separated). Drop filler words. Example: "what database should we use for
      the new service" → `database-decision`.
   3. Confirm with user. Present the derived slug and ask for confirmation or override. Example:
      "Starting decision spike. Branch and objective will be named `database-decision`. Proceed, or
      provide an alternative name?"
   4. Create branch + objective. Read and follow `procedures/create.md` with the confirmed slug as
      the argument. This creates the bookmark and objective and loads it.
   5. Continue. The topic argument carries through to Step 2 (no re-derivation needed).

2. Derive topic. If no topic argument was provided:
   - Read `## Research > ### Questions`, `## Context`, then `## Approach` from `00-main.md` (in
     order).
   - Synthesize a focused interrogate topic from the first section with unresolved items:
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

5. Present summary.
   - Key decisions made this session.
   - Open decisions requiring future resolution.
   - New questions that surfaced during interrogation.
   - Suggest next: more interrogation, or ready for `/objective spec`.

## Contracts

- Writes `## Research > ### Decisions` in `00-main.md` only.
- Preserve the auto-creation nudge, the topic-derivation fallback, and the decisions-merge semantics
  verbatim.
- The interrogate skill is interactive and objective-unaware — all persistence happens in Step 4.
- Run `/objective interrogate` again per topic for separate sessions; the objective accumulates
  state, so nothing is lost between runs.
- Decisions inform Spec and Approach. Do not define ACs here.
