# Reconcile

Use this path for an empty invocation or explicit reconciliation. Reconciliation
has one behavior and accepts no scope, target, or mode.

Read these references before acting:

- `references/local-state.md`
- `references/schema.md`

Reconciliation is a lazy, ordered measurement pass. It establishes current truth
from the beginning of the contract through the first incomplete milestone, then
stops. Exact declared checks, rather than open-ended source investigation, keep
this pass bounded.

Steps:

1. Resolve Local State, read the contract fresh, and stop if its bookmark does
   not match.
2. Validate the structure, identities, milestone order, markers, and declared
   checks. Report any defect without repairing agreement data.
3. Starting with the first milestone, run every unique owned `Check:` exactly
   once against the current checkout when safe and feasible. Reuse one result
   for identical checks. Do not search for alternate proof or substitute another
   check.
4. Stage `[x]` with concise current evidence for a passing AC and `[ ]` with the
   exact failure for a failing AC. Use `[~]` only when the check establishes
   part of the AC. Use `[!]` when the check cannot run safely or completely
   because of an unavailable prerequisite, external blocker, or required user
   decision; name the blocker in evidence.
5. If every AC in the milestone passes, continue to the next milestone. Existing
   `[x]` evidence does not skip remeasurement because the contract stores no
   freshness or change-impact state.
6. At the first milestone with any non-passing AC, stop after measuring all ACs
   in that milestone. Do not inspect later milestones for incidental completion.
7. Atomically apply all staged marker and evidence changes. If no measured state
   changes, leave the contract file unchanged.
8. Derive and report exactly one result:
   - `Complete`: every milestone passed during this reconciliation.
   - `Next: M# - <title>`: produce a self-contained acceptance handoff. Include
     the contract path as provenance, the Spec, applicable durable Context and
     Research, applicable boundaries, the milestone outcome, and every owned AC
     with its declared check and current evidence. Distinguish passing ACs that
     the next work must preserve from non-passing (`[ ]`, `[~]`, or `[!]`) gaps.
     Include preceding milestone outcomes established during this reconciliation
     as preservation constraints. Include every preceding AC statement, check,
     and current evidence that materially guards the next work against
     regression; include all preceding ACs when relevance cannot be bounded
     safely. Do not require a downstream workflow to reload or understand the
     contract schema.

The `Next` result is an acceptance gap, not an implementation proposal. Do not
prescribe how to close it, estimate it, or divide it into tasks. Planning may
consume the outcome, boundaries, ACs, checks, and evidence as authoritative
inputs.

Reconciliation must not edit implementation files, agreement data, commits,
revision descriptions, bookmarks, or branches.
