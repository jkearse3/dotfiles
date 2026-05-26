# Summarize

Synthesize the Summary section for PR descriptions.

## Arguments

- `--auto` — Write the summary without presenting for review (used by automated workflows).

## References

- `references/contracts.md` — § Load Current Objective for the load/nudge gate, and § Invariants.
- `references/phases.md` — § Phase Resolution for reading each phase's content from its linked file.

## Steps

1. Load the current objective per `references/contracts.md` § Load Current Objective. Stop with this
   nudge if no valid objective is active:

   ```text
   No active objective. Want me to load or create one?
   ```

2. Gather context:
   - Read `00-main.md` (Context, Research, Acceptance Criteria, Phases index).
   - Use Phase Resolution to read each phase's content from its linked file (or inline section for
     legacy).
   - Use `/diff-summarize` for file-level diff analysis.

3. Synthesize the Summary:
   - Use research findings and phase approach sections for reasoning and decisions.
   - Use the diff summary to verify actual implementation.
   - Format behavior-first with supporting details:

     ```markdown
     ## Summary
     - What changed from user/system perspective
       - Sub-bullet for causal chain or relationship when needed
     - Another behavior change
     - Third change if applicable

     ### Implementation Notes
     - **Area**: Key technical detail worth knowing
     - **Area**: Another relevant detail
     ```

   - Summary bullets state behavior/value changes; assume no prior context. Focus on behavior
     change, not implementation mechanics.
   - Sub-bullets are optional — use them for causal chains or relationships between changes (e.g.,
     "X required Y which surfaced Z"), not for every bullet.
   - Implementation Notes only include details that help reviewers understand non-obvious choices,
     tradeoffs, or areas needing attention.
   - Omit the Implementation Notes section if changes are self-explanatory.

4. Present for review (skip if `--auto`). Show the summary and ask if it looks good.
   - If changes requested: revise and re-present.
   - If rejected: stop without writing.

5. Write the Summary section to the objective.
   - If a Summary section exists: replace its content.
   - If no Summary section exists: append it as the last section of the file.

6. Report: `Summary written to objective.`

## Contracts

- The Summary is external-facing — assume the reader has no other context.
- Used for PR/MR descriptions.
- Run after implementation is complete, not during planning.
- Preserve verbatim: the `No active objective. Want me to load or create one?` nudge, the `--auto`
  skip behavior, the Summary/Implementation Notes output template, and the
  `Summary written to objective.` report string.
