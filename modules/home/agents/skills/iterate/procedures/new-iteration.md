# New Iteration Creation

Use only when the runbook routes a missing state file, a finalized state with a clear new desired
outcome, or an approved non-terminal replacement to new planning. A finalized state file is closed
state; starting a new iteration may overwrite it without separate replacement approval.

Before acting, read:

- `references/bookmark-placement.md`
- `references/state-file.md`
- `references/readiness.md`

New iterations are plans only. New state files must use `Status: planning`, `Next: planning`, even
when no material uncertainty remains.

New iterations must align before approval. Before requesting activation, pressure-test the plan from
multiple angles until both the agent and user agree there are no approval-relevant holes. Explore
questions, concerns, assumptions, tradeoffs, and stop-before conditions sequentially when each
answer may shape the next question. Do not ask for activation approval until those items are
resolved or explicitly recorded as non-material assumptions that are safe to invalidate during
implementation.

1. If no desired outcome was supplied, ask for it and stop.
2. Classify the request before State File Setup:
   - Ready to plan: outcome is clear enough to draft ACs and boundaries.
   - Needs direct question: one concrete user decision blocks the next useful planning question.
   - Needs alignment pass: the idea is conceptual, branching, high-stakes, or consensus is not yet
     clear.
3. For `Needs direct question`, ask the next question and stop before creating or editing the state
   file.
4. For `Needs alignment pass`, work with the user to resolve the idea into decisions, non-goals,
   examples, risks, and validation expectations. Create the iteration only after both the agent and
   user agree no approval-relevant holes remain.
5. Run Bookmark Placement.
6. Run State File Setup.
7. Draft concise context, research, ACs, approach, and boundaries from the request and repo
   inspection.
8. Run Readiness against ACs, boundaries, context, research, and needed evidence.
9. If material uncertainty prevents a safe planning draft, ask and stop before file creation.
10. Create `Status: planning`, `Next: planning`, including any concrete questions that must be
    resolved before activation.
11. If activation readiness passes and no approval-relevant questions or concerns remain, follow
    Persisted Plan Approval from `references/state-file.md`. Otherwise follow Planning Draft Review.
    Then stop. Do not run implement until later explicit plan approval.
