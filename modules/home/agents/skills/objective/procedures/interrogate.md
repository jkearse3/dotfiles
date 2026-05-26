# Interrogate

Invoke `/interrogate` and merge deliberative decisions into the objective. `/interrogate`
systematically interviews the user — this procedure handles persistence.

Read these format references before executing this procedure:

- `references/index-format.md`
- `references/structure.md`

## Arguments

Optional topic to interrogate. If not provided, derive from objective context or conversation
history.

## Steps

### Step 1: Load objective

Read `.objectives/_current/00-main.md`.

- If objective exists: proceed to Step 2.
- If no objective: run the **auto-creation flow** below, then proceed to Step 2.

**Auto-creation flow** (no active objective):

1. **Require topic**: If no topic argument was provided, nudge: "No active objective. Provide a
   topic to start a decision spike, or want me to load/create an objective?"
2. **Extract slug**: From the topic, extract 2-3 key terms that form a compact, descriptive slug
   (lowercase, hyphen-separated). Drop filler words. Example: "what database should we use for the
   new service" → `database-decision`.
3. **Confirm with user**: Present the derived slug and ask for confirmation or override. Example:
   "Starting decision spike. Branch and objective will be named `database-decision`. Proceed, or
   provide an alternative name?"
4. **Create branch + objective**: Read and follow `procedures/create.md` with the confirmed slug as
   the argument. This creates the bookmark, objective, and loads it.
5. **Continue**: The topic argument carries through to Step 2 (no re-derivation needed).

### Step 2: Derive topic

If no topic argument provided:

- Read `## Research > ### Questions`, `## Context`, and `## Approach` from `00-main.md` (in order)
- Synthesize a focused interrogate topic from the first section with unresolved items:
  - `## Research > ### Questions`: uses unanswered questions to drive deliberation
  - `## Context`: uses stated motivation and background
  - `## Approach`: uses proposed strategy and architecture
- If no objective content provides direction, derive the topic from the conversation history
- If nothing available: "No questions or context to interrogate. Provide a topic or add questions
  first."

### Step 3: Invoke the interrogate skill

Invoke the `interrogate` skill via the Skill tool with the topic from Step 2.

The interrogate skill systematically walks through decisions, recording a log of resolved and
outstanding choices. It is not aware of objectives — all persistence happens here.

Wait for the interrogate session to complete, capturing the full decisions log.

### Step 4: Merge decisions

Merge the deliberative decisions from the interrogation into `## Research > ### Decisions` in
`00-main.md`:

- Append new decisions as `[x]` items (decisions are resolved choices with rationale)
- Append new open items as `[ ]` items (decisions deferred or surfaced during interrogation)
- Dedupe against existing `### Decisions` items — skip any that already appear (content match)
- Do not overwrite or remove existing decisions
- Unlike `/investigate`, no findings, questions, or assumptions are merged — only decisions

### Step 5: Present summary

- Key decisions made during this session
- Open decisions requiring future resolution
- New questions that surfaced during interrogation
- Suggest next: more interrogation, or ready for `/objective spec`

## Outputs

Writes to `00-main.md`:

- `## Research > ### Decisions`

## Notes

- `/interrogate` is an interactive process — it asks questions one at a time until all branches are
  resolved.
- `/interrogate` is not aware of objectives. All persistence happens via Step 4 above.
- For separate interrogation sessions on different topics, invoke `/objective interrogate` multiple
  times.
- The objective is the persistent accumulator — no in-memory state to lose.
- Decisions inform Spec and Approach; don't define ACs here.
