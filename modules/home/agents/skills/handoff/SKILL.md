---
name: handoff
description: >-
  Create, find, or load self-contained prompts for fresh sessions with zero prior context; use when
  the user wants to turn an idea, plan, discussion, or current-session context into an aligned
  handoff with clear purpose, scope, constraints, gaps, validation, and intended outcome.
argument-hint: "[handoff intent, description, path, filename, or slug]"
---

# Handoff

Create, find, or load self-contained fresh-session prompts. A handoff preserves enough context,
scope, constraints, open questions, intended use, and intended outcome that another session can act
without seeing the original conversation.

This is not generic prompt engineering or passive note-taking. Optimize for session handoff quality:
alignment, explicit uncertainty, safe scope, and actionable instructions for a fresh agent or
session.

## Arguments

```
$ARGUMENTS
```

Interpret `$ARGUMENTS` and recent conversation as natural language. Do not require rigid
subcommands.

Infer the user's intent:

- Create a new handoff when the user wants to capture, prepare, write, draft, create, or turn the
  current context into a fresh-session prompt.
- List or find handoffs when the user asks what handoffs exist, asks for recent handoffs, or wants
  to locate a previous handoff.
- Load a handoff when the user asks to open, load, show, use, resume from, or run an existing
  handoff, or when the request contains a path, filename, or unique slug fragment.

If intent is ambiguous, ask one brief clarification question.

## Workflow

1. Infer intent from arguments and conversation.
2. For list or find requests, inspect `.agent/handoffs/` and respond with recent matching artifacts.
3. For load requests, resolve one artifact, read it, and print its complete prompt inline.
4. For new handoffs, gather the purpose, context, scope, constraints, unknowns, and intended
   outcome.
5. Run the Gap Check.
6. Resolve material gaps with the user.
7. Run the Alignment Check.
8. Produce the final handoff prompt only after confirmation, or after explicit permission to proceed
   with stated assumptions.
9. Write the final prompt to `.agent/handoffs/YYYY-MM-DD-HHMM-<short-slug>.md` when file edits are
   available and the destination is clear.

## Gap Check

Before producing a new final prompt, examine whether the handoff is strong enough for a fresh
session with zero prior context.

Look for:

- Missing context.
- Ambiguous purpose.
- Unclear scope.
- Missing use instructions.
- Hidden assumptions.
- Conflicting constraints.
- Undefined outcome.
- Weak validation.
- Risky operations.
- Work that is too broad for one coherent prompt.

When a gap would materially affect the final prompt, do not silently fill it in. Surface the gap,
explain why it matters, and help the user resolve it using whatever clarification, pressure-testing,
or decision-making approach fits the situation.

Ask targeted questions only when the answer is needed. Offer options when the user may need to
choose between valid directions. State assumptions only when they are safe, explicit, and easy for
the user to correct.

## Alignment Check

Before writing a new final prompt, briefly summarize:

- Purpose.
- Scope.
- Constraints.
- Intended outcome.
- Open assumptions.

Ask the user to confirm or correct the summary. Do not produce the final handoff prompt until the
user confirms the purpose, scope, constraints, and expected outcome, or explicitly asks to proceed
with the stated assumptions.

## Artifact

By default, write a new final handoff prompt to:

```text
.agent/handoffs/YYYY-MM-DD-HHMM-<short-slug>.md
```

Use the current local date and 24-hour local time. Derive `<short-slug>` from the task in lowercase
kebab case. If the path already exists, append a numeric suffix such as `-2` before `.md`.

Resolve the repository root with `jj root` when available. Create `<jj-root>/.agent/handoffs/` if
needed. If `jj root` is unavailable, use the current Git repository root when clear. If no clear
repository root exists, ask where to write the handoff before creating files.

Handoff files are local workflow artifacts and must not be tracked. Before writing a handoff file:

1. Ensure repo-local ignore or exclude state covers the whole handoffs directory:

   ```text
   /.agent/handoffs/
   ```

2. In git-backed repositories, prefer `<repo-root>/.git/info/exclude` so the rule stays local and
   tracked project ignore files are not modified.
3. Verify the target handoff path is ignored before writing it.

Stop for user direction if the ignore or exclude rule cannot be written, if the target path cannot
be verified as ignored, or if the repository uses a different local-ignore mechanism that is
unclear.

After writing the file, respond with:

- Handoff path.
- Brief summary.
- Remaining assumptions, if any.

Do not ask the user to manually save or copy the prompt when a file artifact can be written. If file
edits are unavailable, print the complete prompt inline.

## Listing

When the user asks what handoffs exist or asks for recent handoffs, list recent files from
`.agent/handoffs/`, newest first.

Show enough information to choose one:

- Timestamp.
- Slug or filename.
- Path.
- Short title from the first heading in the file, when available without expensive analysis.

If `.agent/handoffs/` does not exist or contains no handoffs, say so directly.

## Loading

When the user wants to load, show, open, resume from, use, or run an existing handoff, resolve the
requested artifact from `.agent/handoffs/`.

Accept:

- An explicit path.
- A filename.
- A unique slug fragment.
- A natural-language description that can be matched against recent handoff filenames.

If one handoff clearly matches, read it and print the complete prompt inline in a fenced markdown
block. Do not summarize unless the user asks for a summary.

After the block, say exactly:

```text
Use this as the task for the fresh session.
```

If the handoff appears stale, incomplete, or contains unresolved assumptions, mention that briefly
after the block.

If multiple handoffs match, show the matches and ask the user to choose. If no handoff matches, say
so and show recent handoffs if available.

## Final Prompt Format

Produce new final handoff prompts with these sections when relevant:

```markdown
# Purpose

# Context

# Scope

# Constraints

# Unknowns

# Information

# Use

# Validation

# Outcome

# Response Guidance
```

Every handoff must include `# Purpose`, `# Use`, and `# Outcome`. Keep the prompt concise, but
complete. Include only facts, decisions, and assumptions the fresh session needs. Omit optional
sections that are not relevant, but do not omit the required sections or produce archival notes.

Informational handoffs are allowed, but they must still be prompts. Direct the fresh session to do
something concrete with the information: produce, decide, validate, explain, compare, plan, review,
or ask targeted follow-up questions.

## Rules

- Assume the fresh session has zero prior context.
- Every handoff is an actionable fresh-session prompt, not an archive or passive note.
- Do not invent facts, files, requirements, or decisions.
- Preserve important uncertainty explicitly.
- Prefer concrete instructions over generic advice.
- Prefer alignment over premature prompt generation.
- Use natural-language intent inference instead of requiring rigid subcommands.
- Support research, coding, review, documentation, debugging, planning, external tool work, and
  other context handoffs, including read-only or informational handoffs.
- Ask targeted questions only when the answer would materially affect the final prompt.
- Offer options when there are multiple valid directions.
- State assumptions only when they are safe, explicit, and easy for the user to correct.
