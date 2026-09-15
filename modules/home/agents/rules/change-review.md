# Change Review

Before finalizing task-owned changes, inspect the complete task diff, confirm
declared criteria, and run checks proportionate to the claims and risks.

For a multi-revision change, inspect and verify each finalized revision in
dependency order, then review the aggregate task change. Use agent judgment to
run checks proportionate to each revision's risks. Checks that are unavailable
or disproportionately expensive may be skipped, but report the affected
revisions, skipped checks, reasons, and residual risks. Best-effort verification
does not permit a known-failing revision.

Use an independent reviewer when its expected benefit exceeds coordination and
verification costs; otherwise review in the owning context.

For fixes to mutable jj history, use a fresh child of the earliest affected
revision where the fix is valid. Verify it there, squash it back, inspect
rebased descendants, and rerun affected checks.

After fixes, repeat only affected verification and review. Do not report
completion until required verification and review are complete, declared
criteria are satisfied, and confirmed findings are resolved.
