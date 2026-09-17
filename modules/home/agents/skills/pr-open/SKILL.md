---
name: pr-open
description: >-
  Prepares or opens a GitHub pull request from finalized Git or jj work. Use
  when asked to draft a PR title or description, push a finalized task branch
  for review, or create a draft or ready pull request.
---

# Open Pull Request

Prepare a reviewable pull request from finalized work. Draft content without
mutation unless the user explicitly asks to open or create the PR.

## Input

```text
$ARGUMENTS
```

## Authority

Interpret requests as follows:

- “Draft,” “prepare,” or “write” a PR title or description: produce a preview
  only.
- “Open” or “create” a PR: push the finalized task head and create a GitHub
  draft PR.
- “Open” or “create” a ready PR: create it ready for review.
- An explicit open/create request authorizes the necessary non-force push of the
  finalized task head and PR creation.
- Do not request redundant confirmation when the publication request and target
  are unambiguous.

Pause when the target, repository, base, head, publication intent, or outgoing
changes are ambiguous.

## Boundaries

- Support GitHub repositories through `gh`.
- Support repositories using jj or Git, following all governing repository and
  VCS instructions.
- Do not edit source files, create commits, rewrite history, finalize work, run
  tests, wait for CI, report CI status, or manage the PR after creation.
- Do not force-push.
- Do not expose agent procedures, internal workflow names, or unsupported
  verification claims in public PR content.

## Preconditions

Before drafting or publishing:

1. Establish the intended repository, task head, and local base from the local
   revision graph.
2. Require the task work to be finalized.
   - In Git, require a clean worktree and index.
   - In jj, require the task bookmark to identify the finalized tip and the
     active working revision to contain no unfinalized task changes.
3. Inspect the complete commit range and effective diff from base to head.
4. Block on unrelated, unexpected, uncertain-ownership, or unfinalized work.
5. Detect any existing PR for the head branch.
   - Report an existing open or draft PR without modifying it.
   - Stop if a merged or closed PR previously used the same head branch.

Drafting requires no remote mutation. Publication additionally requires the base
and head checks below.

## Base and Head

Derive stacked ancestry from the local revision graph rather than assuming the
repository default branch.

Use this order:

1. An explicit user-selected base.
2. The local branch or bookmark directly beneath the task stack.
3. The repository default branch only when the task is directly based on it.

Require the selected base to have a matching remote ref at the expected
revision. Block when the base is unpublished, stale, detached, anonymous, or
ambiguous. Never publish or repair the base automatically.

For publication:

- Inspect the exact outgoing head commits and diff.
- Push only the finalized task branch or bookmark.
- Create its remote ref when absent.
- Block on remote divergence or any push requiring force.

## Convention Discovery

Determine title and description conventions using this precedence:

1. Explicit user instructions
2. Explicit repository instructions and PR templates
3. The defaults in this skill
4. Historical PR sampling only when explicitly requested or when repository
   guidance is ambiguous, contradictory, or refers to undocumented examples

When historical sampling is necessary:

1. Inspect up to five recent merged PRs authored by the authenticated GitHub
   user.
2. If none exist, inspect up to five recent merged repository PRs, preferably
   from different authors.
3. Infer a convention only when the sample is reasonably consistent.

Use history only for presentation conventions. Never infer issue ownership,
reviewers, labels, milestones, projects, or other workflow metadata from prior
PRs.

When a repository supplies a PR template, preserve its required structure and
adapt the generated content to it rather than replacing it blindly.

## Title

Follow an explicit repository title convention when one exists. Otherwise write
a concise imperative statement describing the merged outcome:

```text
Prevent duplicate notification delivery
Simplify configuration resolution
Update development dependencies
```

Do not add a Conventional Commit prefix unless repository evidence calls for
one.

When the work is reliably bound to an external ticket, use:

```text
<TICKET-ID> - <imperative merged outcome>
```

Treat a ticket as bound only when established by one of:

- Explicit user instruction
- Repository or task instructions
- Current branch or bookmark metadata
- Accessible issue-tracker metadata identifying the current branch

Commit-message references alone do not establish issue ownership. Never infer a
ticket from a bare number.

## Description

Use this stable core shape unless a repository template supersedes it:

```markdown
## Summary

<Why this change exists, followed by the high-level solution or outcome.>

## What's Changed

- <Concrete behavior, architecture, or implementation change>
- <Another review-significant change>
```

Write the summary in one or two short paragraphs:

- Lead with the real problem, limitation, need, or maintenance purpose.
- Follow with the solution or resulting outcome.
- For routine work, combine purpose and action in one concise sentence.
- Never manufacture a problem or motivation.
- Avoid repeating the title without adding context.

Use `What's Changed` for reviewer-significant behavior and implementation
details, not a mechanical list of changed files.

Append these sections only when they contain useful information:

```markdown
## Verification

## Risks and Rollout

## Screenshots

## Related

## Review Guide
```

Remove empty or inapplicable sections.

### Verification Evidence

Include verification only when supported by evidence tied to the exact published
content:

- Commands and observed results from the current session
- Exact-head evidence already available in context
- Explicit results supplied by the user

Never infer that checks passed from the presence of tests or configuration. Do
not reuse evidence after the verified content changes.

When no reliable evidence exists, omit `Verification`. If the repository
template requires verification text, stop and ask the user for suitable public
wording rather than inventing a result or exposing internal procedure.

### Related Work

When a ticket binding is established, link it under `Related`.

Use automatic-closing language only when repository instructions, tracker
integration, or explicit user intent establishes that merging this PR should
close the ticket. Otherwise link it without implying complete resolution.

## Metadata

For a newly created PR:

- Assign the authenticated GitHub user by default.
- Create it as a draft unless the user explicitly requests ready-for-review
  status.
- Set reviewers, labels, milestones, or projects only when explicitly requested
  or unambiguously required by current repository instructions.
- Never infer those fields from historical PRs.

## Publication

When explicitly authorized to open or create the PR:

1. Reconfirm the exact repository, base, head, outgoing commits, and draft
   state.
2. Push the finalized task head without force.
3. Create the PR using the generated title and body.
4. Assign the authenticated user.
5. Do not poll checks or perform subsequent status management.

Use safe non-interactive input for the PR body rather than interpolating
Markdown through an unsafe shell command.

If the push succeeds but PR creation fails, report the published branch and the
failure clearly. Do not delete or roll back the branch automatically.

## Result

For a preview, report:

- Proposed title
- Proposed body
- Base and head
- Intended draft or ready state

After publication, report:

- PR URL
- Title
- Base and head
- Draft or ready state
- Assignee

Report blockers precisely and do not broaden the requested operation to resolve
them.
