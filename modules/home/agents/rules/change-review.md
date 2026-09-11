# Change Review

Before finalizing task-owned changes, inspect the complete task diff, confirm
declared criteria, and run checks proportionate to the claims and risks.

Review the finalized aggregate task change. Use an independent reviewer when its
expected benefit exceeds coordination and verification costs; otherwise review
it in the owning context.

For fixes to mutable jj history, use a fresh child of the earliest affected
revision where the fix is valid. Verify it there, squash it back, inspect
rebased descendants, and rerun affected checks.

After fixes, repeat only affected verification and review. Do not report
completion until required verification and review are complete, declared
criteria are satisfied, and confirmed findings are resolved.
