# Iterate

Autonomous outer loop: run a pre-flight confidence gate, then invoke Phase Iterate with
`--auto-commit` repeatedly until all ACs are satisfied.

## References

- `references/contracts.md` — file conventions and invariants.
- `references/acceptance-criteria.md` — AC verifiability and marker semantics.

## Steps

Run in order. Do not improvise or skip steps.

1. Pre-flight confidence gate. Read `.objectives/_current/00-main.md` fresh (never rely on prior
   context). Validate the spec is ready for autonomous execution. Check each condition and collect
   all gaps before stopping.

   Research completeness:
   - All Questions under `### Questions` resolved (no unchecked `[ ]` items).
   - All Assumptions under `### Assumptions` validated (no unchecked `[ ]` items).

   Approach quality:
   - `## Approach` exists and is not placeholder text ("No approach yet", empty, etc.).
   - An agent can scope phases and execute without asking clarifying questions:
     - Sequencing constraints stated.
     - Architectural decisions made (not deferred).
     - Key patterns/libraries identified.
   - Flag as a gap if any of these would require human input to resolve.

   AC verifiability:
   - Each AC is verifiable by code inspection or tests — not vague ("works well", "is fast").
   - ACs requiring human judgment are explicitly marked `(human)`.
   - No `[!]` regressions present.

   If any check fails: list specific gaps and stop. Do not enter the loop.

2. Enter outer loop. While uncompleted `[ ]` ACs remain (excluding `[-]` invalidated ACs):
   1. Read and follow `procedures/phase-iterate.md` with `--auto-commit`.
   2. On `PHASE_COMPLETE`:
      - Re-read `.objectives/_current/00-main.md` to get updated AC state.
      - Check for `[!]` regressions — if any found, stop with a diagnostic listing the regressed
        ACs.
      - Continue to the next iteration (iterate will auto-scope the next phase).
   3. On `PHASE_INCOMPLETE`: stop with a diagnostic — report the phase number, reason, and specific
      blockers.

3. Completion. When no `[ ]` ACs remain (all are `[x]`, `[~]`, or `[-]`):
   1. Read and follow `procedures/summarize.md` with `--auto`.
   2. List any deferred `[~] (human)` ACs that need user sign-off.
   3. Announce: "All phases complete. Run `/objective review` if you want a final review before
      merging."

## Contracts

- Preserve verbatim: the pre-flight gate checks, the `--auto` summarize/phase-iterate invocations,
  the `PHASE_COMPLETE` / `PHASE_INCOMPLETE` handling, and the completion announcement.
- Top-level orchestrator: replaces the user's manual `/objective phase-iterate` loop. All edits
  happen through Phase Iterate; this procedure only reads `00-main.md` and orchestrates.
- `[~] (human)` ACs do not block the loop — they are deferred and listed at completion.
- On `PHASE_INCOMPLETE`, stop immediately. Do not retry — the user must resolve the blocker.
- Resumable: re-invoking `/objective iterate` after a stop reads `00-main.md`, finds completed
  phases already `[x]`, and the focused or next pending phase becomes the loop entry point.
