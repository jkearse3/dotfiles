---
name: handoff
description: >-
  Create, find, show, execute, or resume self-contained prompts for fresh sessions with zero prior
  context; use when a request concerns a continuation artifact while keeping artifact handling
  distinct from execution authority.
argument-hint: "[create, find, show, description, path, filename, or slug]"
---

# Handoff

Transport actionable context into a fresh session. A handoff preserves the purpose, relevant
context, scope, constraints, uncertainty, validation, and intended outcome needed to continue work
without the original conversation.

Creating, finding, or showing a handoff does not execute or resume the work it describes.

## Arguments

```
$ARGUMENTS
```

Interpret `$ARGUMENTS` and recent conversation as natural language. Do not require rigid
subcommands.

Infer the user's intent:

- **Create** when the user wants to capture, prepare, write, draft, or turn supplied or current
  context into a fresh-session prompt.
- **Find** when the user asks what handoffs exist or wants to locate one.
- **Show** when the user asks to read, open, load, or display one without acting on it.
- **Execute or resume** when the user asks to run, use, continue, or resume the work described by a
  handoff. Resolve and read the handoff if needed, then treat its prompt as the task rather than
  treating display as execution.

If the intended operation remains materially ambiguous, ask one brief clarification question.

## Workflow

1. Determine whether the request is create, find, show, or execute/resume.
2. For find, inspect `.agent/handoffs/`, report matching artifacts, and stop.
3. For show, resolve one artifact, print its complete prompt, state that it was only displayed, and
   stop.
4. For execute/resume, resolve and read the handoff, then follow its prompt under the authority of
   the user's execution request. Do not edit the handoff merely to execute it.
5. For create, identify the purpose, authoritative inputs, necessary context, scope, constraints,
   assumptions, validation, intended next action, and outcome.
6. If supplied content is complete and internally consistent, create the handoff without requiring
   confirmation that merely restates it.
7. Ask one targeted question before relying on a material inference, changing scope, or resolving a
   contradiction. Do not silently invent missing facts or decisions.
8. Write the prompt when file mutation is authorized and the destination and ignore state are safe.
   Otherwise print the complete proposed prompt inline and say that no artifact was written.

## Authority

Identify the inputs that govern the handoff and preserve exact user-provided technical content.
Creating a handoff authorizes only the new artifact and any minimum local ignore state needed for
its directory. It does not authorize implementation, revision changes, or mutation of referenced
artifacts.

When a handoff depends on an authoritative external artifact, reference it by path rather than
copying changing state as if it remains current. Label any necessary status excerpt as a snapshot
and direct the fresh session to reload the authoritative artifact before relying on its current
state.

## Artifact

Write new handoffs by default to:

```text
.agent/handoffs/YYYY-MM-DD-HHMM-<short-slug>.md
```

Use the current local date and 24-hour local time. Derive `<short-slug>` from the task in lowercase
kebab case. If the path exists, append a numeric suffix such as `-2` before `.md`.

Resolve the repository root with `jj root` when available. Otherwise use the current Git repository
root when clear. If neither is clear, ask where to write the handoff.

Handoffs are local workflow artifacts and must not be tracked. Before writing:

1. Ensure local ignore or exclude state covers `/.agent/handoffs/`.
2. In a Git-backed repository, prefer `<repo-root>/.git/info/exclude` so tracked ignore files remain
   unchanged.
3. Verify the target path is ignored.

Stop for user direction if local ignore state cannot be safely established or verified. Do not
change the storage location or tracked project ignore files merely to avoid that blocker.

Do not amend an existing handoff. If the user requests a replacement, write a new timestamped
artifact.

After writing, report the path, purpose, intended next action, and any material assumptions.

## Finding

List matching files from `.agent/handoffs/`, newest first. Include the timestamp, filename, path,
and first heading when readily available. If the directory is absent or empty, say so.

## Showing

Resolve an explicit path, filename, unique slug fragment, or clear natural-language match. If
multiple artifacts match, report them and ask the user to choose. If none match, say so and show
recent candidates when available.

Print the complete prompt inline in a fenced Markdown block without summarizing unless requested.
Then state:

```text
Displayed only; no task was executed or resumed.
```

Mention material staleness, incompleteness, unresolved assumptions, or authoritative external
artifacts that should be reloaded.

## Prompt Format

Use these sections when relevant:

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

Every handoff must include `# Purpose`, `# Authoritative Inputs`, `# Use`, and `# Outcome`. `# Use`
must name the intended next action. Omit irrelevant optional sections, but keep enough information
for a fresh session with zero prior context.

Informational handoffs must still request a concrete action such as explain, compare, decide,
validate, plan, or review.

## Rules

- Assume the fresh session has zero prior context.
- Produce an actionable prompt, not an archive or passive note.
- Do not invent facts, files, requirements, decisions, or authority.
- Preserve important uncertainty explicitly.
- Prefer concrete instructions over generic advice.
- Ask only when the answer materially affects the handoff.
- Keep the handoff concise while preserving what the next session needs.
