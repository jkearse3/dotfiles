# Phase Interrogate

Apply the interrogate workflow at the phase level: resolve the focused phase, derive a topic, invoke
the interrogate skill, merge decisions into the phase file, and surface new AC candidates to the
objective.

## Arguments

Optional topic to focus interrogation. If omitted, derive from the focused phase continuation when
it has status `NEEDS_DECISION` with `Scope: phase`; otherwise derive from the full phase content
(Context, Approach, Tasks, Issues).

## References

- `references/current-objective.md` — § Load Current Objective for the active objective gate.
- `references/workflow-invariants.md` — § Continuation Lifecycle and § Invariants for approval gates
  and caller-token preservation.
- `references/auto-scope-dispatch.md` — Auto-scope Dispatch.
- `references/phase-index.md` — Phase Resolution (locate focused phase content).
- `references/phase-file-inputs.md` — Compute Phase-File Inputs and phase-index entry shape.
- `references/objective-index-format.md` — `00-main.md` section layout.
- `references/ac-precision.md` — AC format for new candidates.
- `references/ac-conflict-check.md` — approval-gated conflict checks.

## Steps

1. Load objective. Read `.objectives/_current/00-main.md`.
   - If an objective exists: go to Step 2.
   - If no objective: nudge and stop — "No active objective. Phase-interrogate requires an active
     objective (phases are objective-scoped)."

2. Resolve focused phase. Find the focused phase (`*` in the `## Phases` index in `00-main.md`).
   - If a focused phase exists: resolve its content per `references/phase-index.md` § Phase
     Resolution, then go to Step 3.
   - If no focused phase: run auto-scope dispatch (Step 2a), then go to Step 3.

   Step 2a — Auto-scope dispatch. Run `references/auto-scope-dispatch.md` § Dispatch with these
   procedure-specific results, using the default auto-accept Phase proposal handler:
   - No work remaining: report "Nothing to interrogate." and stop.
   - Readiness issues: surface them and stop.
   - Phase proposal: auto-accept (no user approval), re-read `00-main.md`, resolve the new phase
     content, and go to Step 3.

3. Derive topic. If a topic argument was provided, use it directly. Otherwise:
   - If the focused phase contains `### Continuation` with `Status: NEEDS_DECISION` and phase scope
     in its Payload or Route, use its Summary, Route, Clear when, and any Payload as the default
     interrogation topic and context.
   - Otherwise, read the phase file `### Context`, `### Approach`, `### Tasks`, and `### Issues`.
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
   - Phase file: read the phase file. Add a `### Decisions` section if one does not exist. Append
     resolved decisions as `[x]` items and open items as `[ ]` items. Dedupe against existing
     `### Decisions` items by content match — skip any that already appear. Do not overwrite or
     remove existing decisions. Phase interrogation decisions remain phase-local in `### Decisions`;
     objective-wide decisions remain in `00-main.md` and are owned by the objective-level
     interrogation flow.
   - Objective ACs: for each new AC candidate that surfaced during interrogation, read the existing
     `## Acceptance Criteria` in `00-main.md`, dedupe by content match (exact text match on the
     condition, ignoring numbering and markers), then proceed to Step 5a for conflict checking
     before writing.

   5a. Conflict check. If there are new AC candidates after deduplication, apply
   `references/ac-conflict-check.md` § AC Conflict Check before writing. The new AC candidates are
   the post-deduped objective ACs surfaced during interrogation. Preserve the approval gate:
   conflict analysis and AC candidates require user approval before writing `## Acceptance Criteria`
   in `00-main.md`.

6. Clear or update continuation. After Step 5 has persisted phase-local decisions, and after any
   approved objective AC writes are complete, apply `references/workflow-invariants.md` §
   Continuation Lifecycle for `Status: NEEDS_DECISION` with phase scope.

7. Present summary.
   - Key decisions made this session (from the interrogate log).
   - Open decisions requiring future resolution (from interrogate open items).
   - New AC candidates added to the objective (count and brief list, if any).
   - Continuation cleared or updated, including the next resume route.
   - If no ACs were referenced, nudge: "No ACs were targeted — consider running `/objective spec` to
     define criteria if this design needs validation."
   - Suggest next: more interrogation, or ready for `/objective iterate`.

## Contracts

- Writes to the phase file: `### Decisions` (resolved and open) and, only after decisions are
  persisted, `### Continuation` per `references/workflow-invariants.md` § Continuation Lifecycle.
  Writes to `00-main.md`: `## Acceptance Criteria` (new candidates, deduped, conflict-checked, and
  appended) and, in Step 2a, the `## Phases` index entry.
- Preserve verbatim: the objective-scoped guardrail nudge, the topic-derivation fallback, the
  missing/satisfied-AC nudge, the no-ACs-targeted nudge, the Step 2a no-work message ("Nothing to
  interrogate."), the index entry `P. [ ] [Phase Name](./NN-phase-P.md) *`, and the
  phase-`### Decisions` plus objective-AC merge semantics.
- The guardrail prevents operation without an active objective — phases are objective-scoped.
- Auto-scope dispatch uses the shared auto-accept handler from `references/auto-scope-dispatch.md` §
  Dispatch with no approval gate.
- AC conflict check (Step 5a) is an approval gate — user must approve conflict analysis and new AC
  candidates before any write to `## Acceptance Criteria`; use `references/ac-conflict-check.md` §
  AC Conflict Check.
- Silent merge for phase-file decisions — no confirmation gate, consistent with objective-level
  interrogate.
- The interrogate skill is interactive and objective/phase-unaware — all persistence happens in
  Step 5.
- Focused phase `### Continuation` with `Status: NEEDS_DECISION` and phase scope is the default
  topic and context when no explicit topic argument is provided.
- Phase-local decisions are written to the focused phase `### Decisions`; objective-wide decisions
  remain in `00-main.md` and are owned by objective-level procedures.
- Cross-procedure references read `procedures/interrogate.md`, `procedures/phase-scope.md`, and
  `briefs/phase-scope.md` inline — no recursive Skill tool invocation.
- Missing/satisfied-AC nudges do not block; design exploration is valid without ACs.
