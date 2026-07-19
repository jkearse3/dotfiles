---
name: handoff
description: >-
  Draft, refine, find, show, or execute self-contained prompts for fresh sessions; use when work
  needs to be transported across sessions without treating artifact handling as execution.
argument-hint: "[draft, continue, find, show, execute, path, filename, or slug]"
---

# Handoff

Persist actionable prompts for work that a fresh session must perform with zero prior context. A
handoff remains an ordinary mutable Markdown file; it does not carry lifecycle or execution state.

Creating, refining, finding, showing, or summarizing a handoff never authorizes the work described
by its prompt.

## Arguments

```text
$ARGUMENTS
```

Interpret `$ARGUMENTS` and recent conversation as natural language. Do not require rigid
subcommands.

Infer the requested operation:

- **Create** when the user asks to build a handoff or prompt for a fresh session.
- **Refine** when the user asks to continue, resume, amend, correct, or resolve questions in an
  existing handoff.
- **Find** when the user asks what handoffs exist or wants to locate one.
- **Show or summarize** when the user asks to read, display, explain, or summarize one without
  acting on it.
- **Execute** only when the user explicitly says to `run` or `execute` a handoff and identifies or
  confirms the artifact.

`Continue` or `resume` means refine the prompt, never execute it. Ask one brief question when the
artifact or requested operation remains materially ambiguous.

## Artifacts

Store new handoffs under the repository root:

```text
.agent/handoffs/YYYY-MM-DD-HHMMSS-<short-slug>.md
```

Use the current local time and a concise lowercase kebab-case slug. Add a numeric suffix before
`.md` if the path exists. The filename is an organizational convention, not a validity requirement.

Every Markdown file anywhere under `.agent/handoffs/` is a handoff candidate. Existing nested files
remain ordinary handoffs; directory names such as `drafts/` or `finalized/` carry no special meaning
and require no migration.

Resolve the repository root with `jj root` when available, otherwise with the current Git repository
root. Ask where to store the handoff if neither is clear.

Handoffs are local workflow artifacts and must not be tracked. Before writing:

1. Ensure local ignore or exclude state covers `/.agent/handoffs/`.
2. In a Git-backed repository, prefer `<repo-root>/.git/info/exclude` so tracked ignore files remain
   unchanged.
3. Verify the target is ignored.

Stop for user direction if ignore state cannot be safely established or verified. Do not change the
storage location or tracked ignore files merely to bypass that blocker.

## Drafting

Creating or refining a handoff authorizes only that artifact and the minimum safe local ignore
state. It does not authorize implementation, revision changes, or mutation of referenced artifacts.

When creating a handoff:

1. Identify its purpose, authoritative inputs, context, scope, constraints, uncertainty, validation,
   intended action, and outcome.
2. Write the complete current-best prompt immediately, before extended interrogation can lose the
   starting decisions to context compaction.
3. Ask only about contradictions or omissions that materially affect correctness or the next
   drafting step.

Before every refinement, reread the file and treat it as authoritative over remembered conversation
context. Integrate material decisions, corrections, constraints, and unresolved questions into a
self-contained current-best prompt rather than a chronological transcript.

The user may edit a handoff directly. Always reread before writing. If unexplained edits conflict
with the requested refinement, ask one targeted question instead of overwriting them.

After writing, report the path, purpose, intended next drafting action, and material unresolved
questions. Do not claim that the described task ran.

## Finding And Showing

Resolve an explicit path first, then an exact filename, then a unique slug fragment or clear
natural-language match. Search recursively under `.agent/handoffs/`. Ask the user to choose when
multiple artifacts match. If none match, say so and report recent candidates when readily available.

For a listing, report matching paths and purposes when readily available. When showing an artifact,
print its complete prompt in a fenced Markdown block unless the user requests a summary. Then state:

```text
Displayed only; no task was executed.
```

Mention material staleness, incompleteness, unresolved assumptions, or authoritative external inputs
that an executing session must reload.

## Execution

Execute only after an explicit `run` or `execute` request identifies one handoff or the user
confirms the resolved artifact. Reread its complete contents, report the resolved path, and treat
the prompt as the task under that execution authority.

Execution does not edit, move, rename, annotate, archive, or record status on the handoff. The same
prompt may be executed more than once, and its contents may become stale between executions.

## Prompt Guidance

Use sections such as these when they make the prompt clearer:

```markdown
# Purpose

# Context

# Scope

# Constraints

# Authoritative Inputs

# Assumptions And Unknowns

# Use

# Validation

# Outcome

# Response Guidance
```

These headings are suggestions, not a schema. Include enough information to make the prompt
self-contained and actionable. Reference changing authoritative inputs by path and direct the fresh
session to reload them rather than presenting snapshots as current state.

Informational handoffs must still request a concrete action such as explain, compare, decide,
validate, plan, or review.

## Rules

- Assume the fresh session has zero prior context.
- Produce an actionable prompt, not an archive or passive note.
- Preserve exact user-provided technical text and important uncertainty.
- Do not invent facts, files, requirements, decisions, or authority.
- Prefer concrete instructions over generic advice.
- Keep the handoff concise while preserving what the executing session needs.
- Do not add lifecycle markers, acceptance evidence, progress tracking, ancestry, or execution
  state.
