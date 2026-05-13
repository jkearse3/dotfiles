# Investigate

Invoke `/investigate` and merge structured results into the goal. `/investigate` handles
decomposition and dispatch — this procedure handles persistence.

Read these format references before executing this procedure:

- `references/index-format.md`
- `references/structure.md`

## Arguments

Optional topic to focus research on. If not provided, derive from goal context.

## Steps

### Step 1: Load goal

Read `.goals/_current/00-main.md`.

- If goal exists: proceed to Step 2.
- If no goal: run the **auto-creation flow** below, then proceed to Step 2.

**Auto-creation flow** (no active goal):

1. **Require topic**: If no topic argument was provided, nudge: "No active goal. Provide a topic to
   start a research spike, or want me to load/create a goal?"
2. **Extract slug**: From the topic, extract 2-3 key terms that form a compact, descriptive slug
   (lowercase, hyphen-separated). Drop filler words. Example: "how does the auth middleware handle
   token refresh" → `auth-token-refresh`.
3. **Confirm with user**: Present the derived slug and ask for confirmation or override. Example:
   "Starting research spike. Branch and goal will be named `auth-token-refresh`. Proceed, or provide
   an alternative name?"
4. **Create branch + goal**: Read and follow `procedures/create.md` with the confirmed slug as the
   argument. This creates the bookmark, goal, and loads it.
5. **Continue**: The topic argument carries through to Step 2 (no re-derivation needed).

### Step 2: Derive topic

If no topic argument provided:

- Read `## Context` and `## Research > ### Questions` from `00-main.md`
- Synthesize a focused research topic from gaps and unanswered questions
- If no gaps found: "No questions or research gaps. Provide a topic or add questions first."

### Step 3: Invoke the investigate skill

Invoke the `investigate` skill via the Skill tool with the topic from Step 2.

The investigate skill dispatches subagents and synthesizes results in a single pass. It is not aware
of goals — all persistence happens here.

Wait for the final structured results (Findings, Leads, Questions, Assumptions, Summary).

### Step 4: Merge results

Merge the `/investigate` results into `## Research` section in `00-main.md`:

- **Findings**: Append new findings to `### Findings` (dedupe against existing)
- **Leads**: Append new leads to `### Assumptions` as `[ ]` items (dedupe against existing). Leads
  are unconfirmed hypotheses — they map to assumptions in the goal. Preserve the "what would confirm
  or refute" detail.
- **Questions**: Append new questions to `### Questions` (dedupe against existing)
- **Assumptions**: Append new assumptions to `### Assumptions` (dedupe against existing)
- Do not overwrite existing content — merge additively
- If a finding answers a prior question, remove the question. Factual answers go to **Findings**;
  deliberative choices (picking between options) go to **Decisions** with rationale.
- If a finding validates a prior assumption, remove the assumption and add to **Findings**

### Step 5: Present summary

- Key findings from this research session
- New questions added (if any)
- Questions resolved (moved to findings/decisions)
- Suggest next: more research, or ready for `/goal spec`

## Outputs

Writes to `00-main.md`:

- `## Research > ### Findings`
- `## Research > ### Decisions`
- `## Research > ### Questions`
- `## Research > ### Assumptions` (includes leads merged from `/investigate`)

## Notes

- `/investigate` runs a single pass — it dispatches subagents and synthesizes results.
- `/investigate` is not aware of goals. All persistence happens via Step 4 above.
- For separate research sessions on different topics, invoke `/goal investigate` multiple times.
- The goal is the persistent accumulator — no in-memory state to lose.
- Findings inform Spec; don't define ACs here.
