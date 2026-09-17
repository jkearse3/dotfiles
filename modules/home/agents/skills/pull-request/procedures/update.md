# Update Procedure

Update an open GitHub PR's title, body, or both so its presentation matches the
changes it currently represents.

1. Require one unambiguous open or draft PR. Stop on a merged or closed PR, or
   when the intended PR cannot be distinguished safely.
2. If the user explicitly requested publication before the update, verify that
   the task-owned local branch or bookmark is the PR head, inspect the exact
   outgoing commits and diff, and require the remote head to be an ancestor of
   the finalized local head. Push only that head without force, then verify the
   remote head resolves to the inspected local commit. Stop on divergence or any
   mismatch.
3. Treat the PR's remote base and remote head as authoritative. Retrieve and
   inspect their exact commit identifiers and effective diff. If the finalized
   local head contains unpushed changes and publication was not authorized,
   exclude them and report that the PR does not represent them.
4. Retrieve the current title and body. Compose only the requested replacement
   fields according to `../SKILL.md`.
5. Reconcile rather than blindly regenerate the body:
   - Preserve required template structure, compatible manually authored context,
     issue links, and checklist state.
   - Revise or remove generated claims that are stale after the scope change.
   - Do not silently discard content whose ownership or continued intent is
     uncertain. Stop and present the proposed reconciliation when that
     uncertainty is material.
6. Preview the exact current-to-proposed field changes before mutation. A direct
   and unambiguous update request does not require another confirmation.
7. Immediately before editing, retrieve the PR again and verify that its state,
   base and head identifiers, title, and body still match the inspected values.
   Stop and recompute if any changed concurrently.
8. Update only the requested fields with `gh pr edit`. Supply a changed body
   through a temporary file or equivalent safe non-interactive input. An update
   request alone does not authorize a push, base retarget, draft-state change,
   or metadata change.
9. Retrieve the PR after editing and verify that each requested field exactly
   matches the proposed value and all unrequested fields remain unchanged.
10. Report the PR URL, updated fields and final values, base and head commit
    identifiers used to derive the presentation, preserved manual or template
    content worth calling out, and any excluded unpushed changes, partial
    failures, or verification mismatches.
