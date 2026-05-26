# Investigate

Invoke the `investigate` skill and merge structured results into the objective. The skill handles
decomposition and dispatch; this procedure handles persistence.

## Arguments

Optional topic to focus research on. If omitted, derive from objective context.

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
      Provide a topic to start a research spike, or want me to load/create an objective?"
   2. Extract slug. From the topic, take 2-3 key terms forming a compact, descriptive slug
      (lowercase, hyphen-separated). Drop filler words. Example: "how does the auth middleware
      handle token refresh" → `auth-token-refresh`.
   3. Confirm with user. Present the derived slug and ask for confirmation or override. Example:
      "Starting research spike. Branch and objective will be named `auth-token-refresh`. Proceed, or
      provide an alternative name?"
   4. Create branch + objective. Read and follow `procedures/create.md` with the confirmed slug as
      the argument. This creates the bookmark and objective and loads it.
   5. Continue. The topic argument carries through to Step 2 (no re-derivation needed).

2. Derive topic. If no topic argument was provided:
   - Read `## Context` and `## Research > ### Questions` from `00-main.md`.
   - Synthesize a focused research topic from gaps and unanswered questions.
   - If no gaps are found, stop: "No questions or research gaps. Provide a topic or add questions
     first."

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

5. Present summary.
   - Key findings from this research session.
   - New questions added (if any).
   - Questions resolved (moved to findings/decisions).
   - Suggest next: more research, or ready for `/objective spec`.

## Contracts

- Writes to `00-main.md`: `### Findings`, `### Decisions`, `### Questions`, and `### Assumptions`
  (the last includes leads merged from `/investigate`), all under `## Research`.
- Preserve the research-spike nudge, the no-gaps fallback, and the
  findings/leads/questions/assumptions merge rules verbatim.
- The investigate skill runs a single pass and is objective-unaware — all persistence happens in
  Step 4.
- Run `/objective investigate` again per topic for separate sessions; the objective accumulates
  state, so nothing is lost between runs.
- Findings inform Spec. Do not define ACs here.
