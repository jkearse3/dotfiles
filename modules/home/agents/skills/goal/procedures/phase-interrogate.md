# Phase Interrogate

Apply the interrogate workflow at the phase level: load state, resolve the focused phase, derive a
topic, invoke the interrogate skill, merge decisions into the phase file, and surface new AC
candidates to the goal.

Read these format references before executing this procedure:

- `references/phases.md`
- `references/index-format.md`
- `references/acceptance-criteria.md`

## Arguments

Optional topic to focus interrogation. If not provided, derive from the full phase content (Context,
Approach, Tasks, Issues).

## Steps

### Step 1: Load goal

Read `.goals/_current/00-main.md`.

- If goal exists: proceed to Step 2.
- If no goal: nudge — "No active goal. Phase-interrogate requires an active goal (phases are
  goal-scoped)." and stop.

### Step 2: Resolve focused phase

Find the focused phase (`*` in `## Phases` index in `00-main.md`).

- If focused phase exists: resolve its content per Phase Resolution (`references/phases.md` § Phase
  Resolution). Proceed to Step 3.
- If no focused phase: run auto-scope dispatch (Step 2a), then proceed to Step 3.

#### Step 2a: Auto-scope dispatch

Compute the phase-file path first: follow `references/templates.md` § New Phase → Compute phase-file
inputs.

Dispatch a subagent with prompt:

```
Read the file at ~/.claude/skills/goal/briefs/phase-scope.md and execute the instructions within it.

goal_dir: <absolute path to goal directory>
P: <phase number>
NN: <sequence number, zero-padded>
Phase file: <absolute path to phase file>
```

**On no work remaining**: report "Nothing to interrogate." and stop.

**On readiness issues**: surface them and stop.

**On phase proposal**: auto-accept. The subagent has already written the phase file at the provided
path. Update `00-main.md` immediately by adding a linked index entry to `## Phases`:
`P. [ ] [Phase Name](./NN-phase-P.md) *`. Do not wait for user approval.

Re-read `00-main.md` and resolve the new phase content. Proceed to Step 3.

### Step 3: Derive topic

If a topic argument was provided, use it directly.

If no topic argument:

- Read the phase file (or inline phase section) for `### Context`, `### Approach`, `### Tasks`, and
  `### Issues`
- Synthesize a focused interrogate topic from the full phase content combining all four sections
- If the phase content provides no actionable direction, fall back to the goal-level Context and
  Approach from `00-main.md`
- If nothing available: "No content to interrogate. Provide a topic or populate the phase context
  first."

**Nudge for missing/satisfied ACs**: If the phase has no tasks referencing any AC, or all referenced
ACs are already `[x]`, nudge: "This phase has no pending ACs — interrogation can still surface
design decisions and new AC candidates." Do not block — proceed with the derived topic.

### Step 4: Invoke the interrogate skill

Invoke the `interrogate` skill via the Skill tool with the topic from Step 3.

The interrogate skill systematically walks through decisions, recording a log of resolved and
outstanding choices. It is not aware of goals or phases — all persistence happens here.

Wait for the interrogate session to complete, capturing the full decisions log.

### Step 5: Merge decisions

Merge the deliberative decisions from the interrogation:

**Phase file**: Read the phase file (or inline phase section). Add a `### Decisions` section if one
does not exist. Append:

- Resolved decisions as `[x]` items
- Open items as `[ ]` items

Dedupe against existing `### Decisions` items in the phase file — skip any that already appear
(content match). Do not overwrite or remove existing decisions.

**Goal ACs**: For each new AC candidate that surfaced during interrogation:

- Read the existing `## Acceptance Criteria` in `00-main.md`
- Dedupe against existing ACs by content match — skip any that already appear (exact text match on
  the condition, ignoring numbering and markers)
- Append new unique AC candidates at the next available AC number

Follow the AC format from `references/acceptance-criteria.md`.

### Step 6: Present summary

- Key decisions made during this session (from the interrogate log)
- Open decisions requiring future resolution (from interrogate open items)
- New AC candidates added to goal (count and brief list, if any)
- Nudge if no ACs were referenced: "No ACs were targeted — consider running `/goal spec` to define
  criteria if this design needs validation."
- Suggest next: more interrogation, or ready for `/goal phase-scope` or `/goal phase-iterate`

## Outputs

Writes to:

- Phase file (or inline phase section): `### Decisions` — resolved and open decisions
- `00-main.md`: `## Acceptance Criteria` — new AC candidates (deduped, appended)

## Notes

- Phase-interrogate is interactive (via the interrogate skill) — it asks questions one at a time
- The guardrail prevents operation without an active goal — phases are goal-scoped
- Auto-scope dispatch matches the phase-iterate Step 2 pattern (auto-accept)
- Silent merge: no confirmation gate, consistent with goal-level interrogate
- Cross-procedure references read `procedures/interrogate.md`, `procedures/phase-scope.md`, and
  `briefs/phase-scope.md` inline — no recursive Skill tool invocation
- Nudges on missing/satisfied ACs do not block — design exploration is valid without ACs
