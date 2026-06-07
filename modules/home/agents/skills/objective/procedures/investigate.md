# Investigate

Invoke the `investigate` skill and merge structured results into the objective. The skill handles
decomposition and dispatch; this procedure handles persistence.

## Arguments

Optional topic to focus research on. If omitted, derive from focused phase continuation when it has
status `NEEDS_RESEARCH`; otherwise derive from objective context.

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
   - Spike kind: `research spike`.
   - Require-topic nudge: "No active objective. Provide a topic to start a research spike, or want
     me to load/create an objective?"
   - Slug example: "how does the auth middleware handle token refresh" → `auth-token-refresh`.
   - Confirmation example: "Starting research spike. Branch and objective will be named
     `auth-token-refresh`. Proceed, or provide an alternative name?"
   - Create argument: confirmed slug.

2. Derive topic. If no topic argument was provided:
   - If a focused phase exists and contains `### Continuation` with `Status: NEEDS_RESEARCH`, use
     its Summary, Route, Clear when, and any Payload as the default research topic and context.
   - Otherwise, read `## Context` and `## Research > ### Questions` from `00-main.md`, then
     synthesize a focused research topic from gaps and unanswered questions.
   - If no continuation context or objective gaps are found, stop: "No questions or research gaps.
     Provide a topic or add questions first."

3. Invoke the investigate skill via the Skill tool with the topic from Step 2. The skill dispatches
   subagents and synthesizes results in a single pass. It is not aware of objectives. Wait for the
   final structured results (Findings, Leads, Questions, Assumptions, Summary).

4. Merge results into `## Research` in `00-main.md`. Merge additively — do not overwrite existing
   content.
   - Findings: append new findings to `### Findings` (dedupe against existing).
   - Leads: append new leads to `### Assumptions` as `[ ]` items (dedupe against existing). Leads
     are unconfirmed hypotheses — they map to assumptions. Preserve the "what would confirm or
     refute" detail.
   - Questions: append new questions to `### Questions` (dedupe against existing).
   - Assumptions: append new assumptions to `### Assumptions` (dedupe against existing).
   - If a finding answers a prior question, remove the question. Factual answers go to Findings;
     deliberative choices (picking between options) go to Decisions with rationale.
   - If a finding validates a prior assumption, remove the assumption and add it to Findings.

5. Clear or update continuation. After Step 4 has persisted objective-wide research results to
   `00-main.md`, apply `references/contracts.md` § Continuation Lifecycle for
   `Status: NEEDS_RESEARCH`.

6. Present summary.
   - Key findings from this research session.
   - New questions added (if any).
   - Questions resolved (moved to findings/decisions).
   - Continuation cleared or updated, including the next resume route when applicable.
   - Suggest next: more research, or ready for `/objective spec`.

## Contracts

- Writes to `00-main.md`: `### Findings`, `### Decisions`, `### Questions`, and `### Assumptions`
  (the last includes leads merged from `/investigate`), all under `## Research`. Writes to the
  focused phase file: `### Continuation`, per `references/contracts.md` § Continuation Lifecycle.
- Preserve the research-spike nudge, the no-gaps fallback, and the
  findings/leads/questions/assumptions merge rules verbatim.
- The investigate skill runs a single pass and is objective-unaware — all persistence happens in
  Step 4.
- Run `/objective investigate` again per topic for separate sessions; the objective accumulates
  state, so nothing is lost between runs.
- Findings inform Spec. Do not define ACs here.
- Focused phase `### Continuation` with `Status: NEEDS_RESEARCH` is the default topic and context
  when no explicit topic argument is provided.
