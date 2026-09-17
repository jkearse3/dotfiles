---
name: pull-request
description: >-
  Drafts, creates, or updates a GitHub pull request from finalized Git or jj
  work. Use when asked to prepare a PR title or description, publish a draft or
  ready PR, or refresh an existing PR's title and body to match its represented
  changes.
---

# Pull Request

Produce an accurate review surface for finalized work. Draft presentation
without mutation unless the user explicitly requests PR creation or an update to
an existing PR.

Infer and confirm:

- **Operation**: draft, create, or update.
- **Target**: repository, base, head, and existing PR when applicable.
- **Presentation fields**: title and body. A generic request to refresh or
  update PR presentation includes both; a field-specific request changes only
  that field.
- **Publication intent**: preview only, create as draft or ready, or mutate an
  existing PR.

Interpret authority as follows:

- “Draft,” “prepare,” or “write” a PR title or description authorizes preview
  only.
- “Open” or “create” a PR authorizes the necessary non-force push of the
  finalized task head and creation of a draft PR.
- “Open” or “create” a ready PR additionally authorizes ready-for-review state.
- “Update,” “revise,” or “refresh” an existing PR authorizes changing only the
  requested presentation fields. It does not authorize pushing commits or
  changing other PR state or metadata.
- An explicit combined request to publish finalized commits and update their PR
  authorizes both operations, in that order.

Do not request redundant confirmation when the operation, target, fields, and
publication intent are unambiguous. Stop when any of them is materially
ambiguous.

## Runbook

1. Establish the repository mode, task-owned head, intended base, publication
   state, and operation from local history and explicit context. Follow all
   governing repository and VCS instructions.
2. Require the relevant work to be finalized.
   - In Git, require a clean worktree and index.
   - In jj, require the task bookmark to identify the finalized tip and the
     active working revision to contain no unfinalized task changes.
3. Locate any PR associated with the head branch and inspect its state, URL,
   base, head, title, body, and base/head commit identifiers. Do not assume that
   branch-name association alone identifies the intended PR when history or
   remotes are ambiguous.
4. Resolve the represented change set:
   - For an unpublished draft or new PR, inspect the complete local commit range
     and effective diff from the selected base to the finalized head.
   - For an existing PR, inspect the effective diff between the PR's remote base
     and remote head. Unpushed local commits are not represented by the PR.
5. Inspect the complete represented diff, commits, and relevant repository
   guidance before writing. Block on unrelated, unexpected, uncertain-ownership,
   or unfinalized work.
6. Discover conventions and compose presentation according to the sections
   below. Ground every material claim in the represented change set or explicit
   user-supplied context.
7. Select and read exactly one procedure:
   - `procedures/draft.md` to preview presentation without remote mutation.
   - `procedures/create.md` to push a finalized head and create a PR.
   - `procedures/update.md` to change title, body, or both on an existing PR.
8. Execute only the selected procedure and report its specified result.

## Base and Head

Derive stacked ancestry from the local revision graph rather than assuming the
repository default branch. Select a base in this order:

1. An explicit user-selected base.
2. The local branch or bookmark directly beneath the task stack.
3. The repository default branch only when the task is directly based on it.

For creation, require the selected base to have a matching remote ref at the
expected revision. Block when it is unpublished, stale, detached, anonymous, or
ambiguous. Never publish or repair the base automatically.

For an existing PR, its remote base and head define the represented change set.
Do not silently retarget the base, substitute a local diff, or describe commits
that the PR does not yet contain.

## Convention Discovery

Determine title and body conventions using this precedence:

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
reviewers, labels, milestones, projects, or workflow metadata from prior PRs.
Preserve the required structure of a repository PR template.

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

Treat a ticket as bound only when established by explicit user or repository
instructions, current branch or bookmark metadata, or accessible issue-tracker
metadata identifying the current branch. Commit-message references alone do not
establish issue ownership. Never infer a ticket from a bare number.

## Body

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

Remove empty or inapplicable sections unless a repository template requires
them.

### Verification Evidence

Include verification only when supported by evidence tied to the exact
represented content:

- Commands and observed results from the current session
- Exact-head evidence already available in context
- Explicit results supplied by the user

Never infer that checks passed from the presence of tests or configuration. Do
not reuse evidence after the verified content changes. If a template requires
verification text but reliable evidence is unavailable, stop and ask for
suitable public wording rather than inventing a result or exposing internal
procedure.

### Related Work

When a ticket binding is established, link it under `Related`. Use
automatic-closing language only when repository instructions, tracker
integration, or explicit user intent establishes that merging this PR should
close the ticket. Otherwise link it without implying complete resolution.

## Boundaries

- Support GitHub repositories through `gh` and repositories using jj or Git.
- Do not edit source files, implement or repair changes, create commits, rewrite
  history, finalize work, run tests, wait for CI, report CI status, merge or
  close PRs, manage reviews, or delete branches.
- After creation, change only title or body through the update procedure. Do not
  change base, draft/ready state, reviewers, assignees, labels, milestones,
  projects, or other metadata.
- Never force-push.
- Preserve unrelated and uncertain-ownership work by stopping rather than
  absorbing, resetting, stashing, or discarding it.
- Do not expose agent procedures, internal workflow names, or unsupported
  verification claims in public PR content.
- Use safe non-interactive input for bodies rather than interpolating Markdown
  through an unsafe shell command.
