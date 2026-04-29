# Iterate

Autonomous outer loop that invokes Phase Iterate with `--auto-commit` repeatedly until all ACs are
satisfied. Runs a pre-flight confidence gate before entering the loop.

Read this format reference before executing this procedure:

- `${CLAUDE_SKILL_DIR}/references/acceptance-criteria.md`

## Execution

Run these steps in order. Do not improvise or skip steps.

### Step 1: Pre-flight Confidence Gate

Read `.claude/_goals/_current/00-main.md` fresh (never rely on prior context).

Validate the spec is ready for autonomous execution. Check each condition and collect all gaps
before stopping.

**Research completeness**:

- All Questions under `### Questions` must be resolved (no unchecked `[ ]` items)
- All Assumptions under `### Assumptions` must be validated (no unchecked `[ ]` items)

**Approach quality**:

- `## Approach` must exist and not be placeholder text ("No approach yet", empty, etc.)
- Evaluate whether an agent can scope phases and execute without asking clarifying questions:
  - Are sequencing constraints stated?
  - Are architectural decisions made (not deferred)?
  - Are key patterns/libraries identified?
- If any of these would require human input to resolve, flag as a gap.

**AC verifiability**:

- Each AC must be verifiable by code inspection or tests — not vague ("works well", "is fast")
- ACs requiring human judgment must be explicitly marked `(human)`
- `[!]` regressions must not be present

**If any check fails**: List specific gaps and stop. Do not enter the loop.

### Step 2: Enter Outer Loop

While uncompleted `[ ]` ACs remain (excluding `[-]` invalidated ACs):

1. Read and follow `${CLAUDE_SKILL_DIR}/procedures/phase-iterate.md` with `--auto-commit`
2. On `PHASE_COMPLETE`:
   - Re-read `.claude/_goals/_current/00-main.md` to get updated AC state
   - Check for `[!]` regressions — if any found, stop with diagnostic listing the regressed ACs
   - Continue to next iteration (iterate will auto-scope the next phase)
3. On `PHASE_INCOMPLETE`: stop with diagnostic — report the phase number, reason, and specific
   blockers

### Step 3: Completion

When no `[ ]` ACs remain (all are `[x]`, `[~]`, or `[-]`):

1. Read and follow `${CLAUDE_SKILL_DIR}/procedures/summarize.md` with `--auto`
2. List any deferred `[~] (human)` ACs that need user sign-off
3. Announce: "All phases complete. Run `/goal review` if you want a final review before merging."

## Rules

- This procedure is the top-level orchestrator — do NOT use `context: fork`. It replaces the user's
  manual `/goal phase-iterate` loop.
- `[~] (human)` ACs do not block the loop. They are deferred and listed at completion.
- Re-invoking `/goal iterate` after a stop resumes naturally: it reads `00-main.md`, finds completed
  phases already `[x]`, and the focused or next pending phase becomes the loop entry point.
- All edits happen through the Phase Iterate procedure. This procedure only reads `00-main.md` and
  orchestrates.
- If Phase Iterate returns `PHASE_INCOMPLETE`, stop immediately. Do not retry — the user must
  resolve the blocker.
