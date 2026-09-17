# Draft Procedure

Preview PR presentation without mutating local history, remotes, or GitHub.

1. Determine whether the preview is for a new PR or an existing PR.
   - For a new PR, use the finalized local base-to-head change set.
   - For an existing PR, use the change set represented by its remote base and
     head. Retrieve its current title and body for comparison.
2. Compose the requested title, body, or both according to `../SKILL.md`.
3. For an existing PR, reconcile useful current content with the represented
   changes. Preserve required template structure, compatible manual context,
   issue links, and checklist state. Remove or revise stale claims. If a safe
   distinction between intentional manual content and stale generated content
   cannot be made, identify the ambiguity rather than proposing silent loss.
4. Report:
   - Proposed title and body, limited to the requested fields
   - Base and head, including exact commit identifiers when available
   - Existing PR URL and current-to-proposed field changes, when applicable
   - Intended draft or ready state for a new PR
   - Blockers, ambiguities, and excluded unpushed local changes

Do not push, create a PR, or call any mutating `gh` operation.
