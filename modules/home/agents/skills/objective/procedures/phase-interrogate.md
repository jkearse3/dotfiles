# Phase Interrogate

Apply the interrogate workflow at the phase level: resolve the focused phase, derive a topic, invoke
the interrogate skill, merge decisions into the phase file, and surface new AC candidates to the
objective.

## Arguments

Optional topic to focus interrogation. If omitted, derive from the full phase content (Context,
Approach, Tasks, Issues).

## References

- `references/contracts.md` — file conventions, Load Current Objective, Auto-scope Dispatch, and
  invariants.
- `references/phases.md` — Phase Resolution (locate focused phase content).
- `references/templates.md` — New Phase (compute phase-file inputs before dispatch).
- `references/index-format.md` — `00-main.md` section layout and marker semantics.
- `references/acceptance-criteria.md` — AC format for new candidates.

## Steps

1. Load objective. Read `.objectives/_current/00-main.md`.
   - If an objective exists: go to Step 2.
   - If no objective: nudge and stop — "No active objective. Phase-interrogate requires an active
     objective (phases are objective-scoped)."

2. Resolve focused phase. Find the focused phase (`*` in the `## Phases` index in `00-main.md`).
   - If a focused phase exists: resolve its content per `references/phases.md` § Phase Resolution,
     then go to Step 3.
   - If no focused phase: run auto-scope dispatch (Step 2a), then go to Step 3.

   Step 2a — Auto-scope dispatch. Run `references/contracts.md` § Auto-scope Dispatch with these
   procedure-specific results:
   - No work remaining: report "Nothing to interrogate." and stop.
   - Readiness issues: surface them and stop.
   - Phase proposal: auto-accept (no user approval). The subagent has already written the phase file
     at the computed path. Update `00-main.md` immediately by adding a linked index entry to
     `## Phases`: `P. [ ] [Phase Name](./NN-phase-P.md) *`. Then re-read `00-main.md`, resolve the
     new phase content, and go to Step 3.

3. Derive topic. If a topic argument was provided, use it directly. Otherwise:
   - Read the phase file (or inline phase section) `### Context`, `### Approach`, `### Tasks`, and
     `### Issues`.
   - Synthesize a focused interrogate topic from the full phase content, combining all four
     sections.
   - If the phase content provides no actionable direction, fall back to the objective-level Context
     and Approach from `00-main.md`.
   - If nothing is available, stop: "No content to interrogate. Provide a topic or populate the
     phase context first."

   Nudge for missing/satisfied ACs: if the phase has no tasks referencing any AC, or all referenced
   ACs are already `[x]`, nudge: "This phase has no pending ACs — interrogation can still surface
   design decisions and new AC candidates." Do not block — proceed with the derived topic.

4. Invoke the interrogate skill via the Skill tool with the topic from Step 3. The skill walks
   through decisions one at a time, recording resolved and outstanding choices. It is not aware of
   objectives or phases. Wait for the session to complete, capturing the full decisions log.

5. Merge decisions.
   - Phase file: read the phase file (or inline phase section). Add a `### Decisions` section if one
     does not exist. Append resolved decisions as `[x]` items and open items as `[ ]` items. Dedupe
     against existing `### Decisions` items by content match — skip any that already appear. Do not
     overwrite or remove existing decisions.
   - Objective ACs: for each new AC candidate that surfaced during interrogation, read the existing
     `## Acceptance Criteria` in `00-main.md`, dedupe by content match (exact text match on the
     condition, ignoring numbering and markers), then proceed to Step 5a for conflict checking
     before writing.

   5a. Conflict check. If there are new AC candidates after deduplication, scan existing ACs for
   conflicts before writing:
   - For each existing AC, check if any new AC candidate contradicts, overlaps with, or supersedes
     it.
   - **Unlocked ACs** (marker is `[ ]` and no task references `(ACN, ...)`): update in place.
   - **Locked ACs** (marker is not `[ ]`, or task references exist): invalidate using `[-]` +
     strikethrough + cross-reference per the AC stability rules in
     `references/acceptance-criteria.md`.

   Present the conflict analysis to the user: which ACs will be updated, which invalidated, and what
   new ACs will be added. Require user approval before writing. If no conflicts: present the drafted
   AC candidates for user approval.

   After approval, write all ACs (existing + new, with any updates/invalidations applied) to
   `## Acceptance Criteria` in `00-main.md`, numbering new ACs sequentially after the highest
   existing AC number. Follow `references/acceptance-criteria.md`.

6. Present summary.
   - Key decisions made this session (from the interrogate log).
   - Open decisions requiring future resolution (from interrogate open items).
   - New AC candidates added to the objective (count and brief list, if any).
   - If no ACs were referenced, nudge: "No ACs were targeted — consider running `/objective spec` to
     define criteria if this design needs validation."
   - Suggest next: more interrogation, or ready for `/objective phase-scope` or
     `/objective phase-iterate`.

## Contracts

- Writes to the phase file (or inline phase section): `### Decisions` (resolved and open). Writes to
  `00-main.md`: `## Acceptance Criteria` (new candidates, deduped, conflict-checked, and appended)
  and, in Step 2a, the `## Phases` index entry.
- Preserve verbatim: the objective-scoped guardrail nudge, the topic-derivation fallback, the
  missing/satisfied-AC nudge, the no-ACs-targeted nudge, the Step 2a no-work message ("Nothing to
  interrogate."), the index entry `P. [ ] [Phase Name](./NN-phase-P.md) *`, and the
  phase-`### Decisions` plus objective-AC merge semantics.
- The guardrail prevents operation without an active objective — phases are objective-scoped.
- Auto-scope dispatch matches the phase-iterate pattern (auto-accept, no approval gate).
- AC conflict check (Step 5a) is an approval gate — user must approve conflict analysis and new AC
  candidates before any write to `## Acceptance Criteria`.
- Silent merge for phase-file decisions — no confirmation gate, consistent with objective-level
  interrogate.
- The interrogate skill is interactive and objective/phase-unaware — all persistence happens in
  Step 5.
- Cross-procedure references read `procedures/interrogate.md`, `procedures/phase-scope.md`, and
  `briefs/phase-scope.md` inline — no recursive Skill tool invocation.
- Missing/satisfied-AC nudges do not block; design exploration is valid without ACs.
