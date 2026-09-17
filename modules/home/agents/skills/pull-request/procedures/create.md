# Create Procedure

Publish a finalized task head and create a new GitHub pull request.

1. Require that no open or draft PR already exists for the head branch. If one
   exists, report it without modification. Stop if a merged or closed PR
   previously used the same head branch.
2. Reconfirm the exact repository, remote, base, task-owned head, outgoing
   commits, effective diff, requested draft state, and generated presentation.
3. Verify that the base's expected local revision matches its remote ref. Push
   only the finalized task branch or bookmark, creating its remote ref when
   absent. Stop on remote divergence or any push requiring force.
4. Confirm that the published head resolves to the inspected finalized commit.
   If it does not, stop without creating the PR.
5. Create the PR with the generated title and body. Pass the body through a
   temporary file or equivalent safe non-interactive input.
6. Assign the authenticated GitHub user. Create the PR as draft unless the user
   explicitly requested ready-for-review state. Set no other metadata unless it
   is explicitly requested and unambiguously required by repository
   instructions.
7. Retrieve the created PR and verify its URL, title, body, base, head, draft
   state, and assignee.
8. Report:
   - PR URL and title
   - Base and head
   - Draft or ready state
   - Assignee
   - Any mismatch or partial failure

Do not poll checks or perform subsequent PR management. If the push succeeds but
PR creation fails, report the published branch and failure clearly; do not
delete or roll back the branch.
