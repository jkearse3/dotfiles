# Summarize

Synthesize Summary section for PR descriptions.

Read this format reference before executing this procedure:

- `references/phases.md`

## Arguments

- `--auto` — Write summary without presenting for review (used by automated workflows)

## Steps

1. **Load objective**: `.objectives/_current/00-main.md`
   - If symlink broken: nudge — "No active objective. Want me to load or create one?"

2. **Gather context**:
   - Read `00-main.md` (Context, Research, Acceptance Criteria, Phases index)
   - Use Phase Resolution to read each phase's content from its linked file (or inline section for
     legacy)
   - Use `/diff-summarize` for file-level diff analysis

3. **Synthesize Summary**:
   - Use research findings and phase approach sections for reasoning and decisions
   - Use diff summary to verify actual implementation
   - Format: behavior-first with supporting details

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

   - Summary bullets: behavior/value changes, assume no prior context. Focus on behavior change, not
     implementation mechanics.
   - Sub-bullets are optional — use them for causal chains or relationships between changes (e.g.,
     "X required Y which surfaced Z"), not for every bullet
   - Implementation Notes: only include details that help reviewers understand non-obvious choices,
     tradeoffs, or areas needing attention
   - Omit Implementation Notes section if changes are self-explanatory

4. **Present for review** (skip if `--auto`): Show summary, ask if it looks good
   - If changes requested: revise and re-present
   - If rejected: stop without writing

5. **Write**: Write Summary section to objective
   - If Summary section exists: replace content
   - If no Summary section: append as last section of the file

6. **Report**: "Summary written to objective."

## Notes

- Summary is external-facing — assume reader has no other context
- Used for PR/MR descriptions
- Run after implementation is complete, not during planning
