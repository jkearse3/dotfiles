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

1. If no desired outcome was supplied, ask for it and stop.
2. Run Bookmark Placement.
3. Run State File Setup.
4. Draft concise context, research, ACs, approach, and boundaries from the request and repo
   inspection.
5. Run Readiness against ACs, boundaries, context, research, and needed evidence.
6. If material uncertainty prevents a safe planning draft, ask and stop before file creation.
7. Create `Status: planning`, `Next: planning`, including any concrete questions that must be
   resolved before activation.
8. Follow Persisted Plan Approval from `references/state-file.md`, then stop. Do not run implement
   until later explicit plan approval.
