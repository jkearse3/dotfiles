# Change Review

Before finalizing task-owned changes, review the complete task diff for defects:
trace it as steps 2 to 5 of `diff-review`'s `references/reviewer.md` do, and
judge it by `references/findings.md`. Fix what you find, and report the
suspected defects you could not settle. Then confirm declared criteria and run
the checks Running Checks calls for. When delegates built the task's diffs and
each reviewed its own this way, the session that lands them relies on those
reviews instead of reviewing the diffs or their aggregate itself.

Recheck every name the task introduced against the final behavior before
finalizing, and rename task-introduced names that describe an earlier
understanding. Renaming them before finalization is within the task's scope.

For a multi-revision change, inspect and verify each finalized revision in
dependency order, then review the aggregate task change. Use agent judgment to
run checks proportionate to each revision's risks. Checks that are unavailable
or disproportionately expensive may be skipped, but report the affected
revisions, skipped checks, reasons, and residual risks. Best-effort verification
does not permit a known-failing revision.

For fixes to mutable jj history, use a fresh child of the earliest affected
revision where the fix is valid. Verify it there, squash it back, inspect
rebased descendants, and rerun affected checks.

After fixes, repeat only affected verification and review. Do not report
completion until required verification and review are complete, declared
criteria are satisfied, and confirmed findings are resolved.

## Responding To Feedback

Judge each review suggestion by what the repository would look like with it:
better, no worse, or worse. Make every suggestion that leaves it better or no
worse. A suggestion doesn't need to fix a defect: a nit, a readability nudge, or
hardening for a path the code doesn't reach today all qualify. Decline only with
evidence that the change makes the repository worse, such as when it is wrong,
breaks or narrows behavior, weakens safety or performance, adds complexity or
maintenance its benefit doesn't justify, or contradicts a recorded decision or
the repository's conventions. "Not needed today" is never a reason to decline a
change within the request's scope. When a suggestion reaches beyond the
request's scope, ask the user whether to include it or take it as follow-up
work.
