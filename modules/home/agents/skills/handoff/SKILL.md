---
name: handoff
description: >-
  Draft, refine, find, show, reconcile readiness for, or execute self-contained
  prompts for fresh sessions; use when work needs to be transported across
  sessions without treating artifact handling as execution.
argument-hint:
  "[draft, continue, find, show, readiness, execute, path, filename, or slug]"
---

# Handoff

Transfer one actionable goal to a fresh session with zero prior context. A
handoff is an ignored, ordinary, mutable Markdown prompt, not workflow state.

Creating, refining, finding, showing, or summarizing a handoff never authorizes
the work described by its prompt.

## Arguments

```text
$ARGUMENTS
```

Interpret `$ARGUMENTS` and recent conversation as natural language. Do not
require rigid subcommands. Infer the operation:

- Create for a new handoff or fresh-session prompt.
- Refine for `continue`, `resume`, amend, correct, or resolve-question intent.
- Find, show, or summarize without acting on the prompt.
- Reconcile readiness when explicitly requested.
- Execute only when the user explicitly says `run` or `execute` and identifies
  or confirms one handoff.

`Continue` or `resume` means refine the prompt, never execute it. Ask one brief
question when the artifact or requested operation remains materially ambiguous.

## Shared Contract

Resolve canonical storage by running `lib/resolve-store.sh` relative to this
skill's directory. It prints the Git main worktree, the non-Git jj `default`
workspace, or the sole jj workspace. If it reports ambiguous jj workspaces, ask
the user to choose one and resolve that named workspace; never guess. If it
reports no repository, ask where to store the handoff.

Store handoffs below the resolved root:

```text
.agent/handoffs/YYYY-MM-DD-HHMMSS-<short-slug>.md
```

Use the current local time and a concise lowercase kebab-case slug. Add a
numeric suffix before `.md` if the path exists. The filename is an
organizational convention, not a validity requirement.

Every Markdown file recursively below `.agent/handoffs/` is a candidate. Nested
directories and names such as `drafts` or `finalized` have no lifecycle meaning.
Do not migrate existing handoffs.

- Assume the fresh session has zero prior context.
- Require one explicit or safely inferable next-session goal and intended
  outcome. Ask one focused question when materially different goals remain.
- Require one concrete first action after orientation.
- Include scope, material exclusions, constraints, authoritative inputs to
  reload, and observable validation. Add context, decisions, assumptions,
  blockers, risks, or response guidance only when useful.
- Verify checkable paths, symbols, revisions, repository facts, completion
  claims, and validation claims proportionately before writing them. Mark
  material claims unverified when safe confirmation is unavailable.
- Preserve exact user-provided technical text and important uncertainty.
- Never copy secrets or personally identifiable information into a handoff.
  Redact values such as credentials, tokens, cookies, private keys, `.env`
  values, and personal details while preserving safe context such as service
  names, variable names, file paths, and retrieval instructions.
- Treat rationale and decisions as session context, not repository facts.
- Prefer paths and symbols over fragile line numbers. Do not perform unrelated
  research or implementation merely to fill sections.
- Keep the prompt concise, actionable, and current rather than archival.
- Do not add lifecycle markers, acceptance evidence, progress tracking,
  ancestry, or execution state.
- Never edit, move, annotate, archive, consume, or record execution on a
  handoff.

## Procedures

Read only the procedure selected for the requested operation:

- `procedures/create-refine.md` for creation or refinement.
- `procedures/receive.md` for finding, listing, showing, summarizing, readiness
  reconciliation, or execution.
