---
name: handoff
description: >-
  Create or execute a concise, self-contained prompt for a fresh session. Use
  when the user asks for a handoff, wants to resume in a new session, or
  explicitly asks to execute a handoff file.
argument-hint: "[next-session goal or execute <path>]"
---

# Handoff

Transfer one actionable goal to a fresh session with zero prior context. A
handoff is an ignored, ordinary Markdown prompt, not workflow state.

Creating a handoff never authorizes the work described by its prompt.

## Arguments

```text
$ARGUMENTS
```

Interpret `$ARGUMENTS` and recent conversation as natural language:

- Create by default. Infer one next-session goal from the recent conversation.
  Ask one focused question only when no single goal is safely inferable.
- Execute only when the user explicitly says `run` or `execute` and identifies a
  handoff.
- An explicit request to show, find, summarize, or edit a handoff authorizes
  only that ordinary file operation, never execution.

## Create

1. Choose a concise lowercase kebab-case slug for the goal. Run
   `scripts/prepare-path.sh --workspace <target-repo> <slug>`, passing the
   absolute path of the repository you are working in as `<target-repo>`. Invoke
   the script by its path; it is independent of the current working directory
   and never derives the target from where it runs. It resolves canonical
   storage, safely prepares the ignored store, and prints the new absolute path.
   If it reports ambiguous storage or a safety failure, stop and report that
   error rather than bypassing it.
2. Write a concise prompt to that path using the structure below. Use recent
   conversation as session context; inspect only an important path or claim
   whose correctness is genuinely uncertain. Mark other uncertainty explicitly
   instead of reconstructing the repository or rerunning validation.
3. Report the absolute path and this two-line pickup text:

```text
Next session:
Execute <absolute-handoff-path>
```

Creating the local store and handoff is the full authorized mutation. Do not
perform the described task or modify revision history.

## Execute

Execution requires an explicit `run` or `execute` request identifying one
handoff. Resolve an explicit path directly. Otherwise run
`scripts/resolve-store.sh --workspace <target-repo>`, passing the absolute path
of the repository you are working in as `<target-repo>`. Invoke the script by
its path; it is independent of the current working directory and never derives
the target from where it runs. Then match an exact filename or unique slug below
`<canonical-root>/.agent/handoffs/`. Preserve the resolver's ambiguity and
failure handling, and ask the user to choose when multiple files match.

1. Read the complete handoff and report its resolved absolute path.
2. Reload every path under `Read` and inspect current repository state needed to
   identify material drift. Do not repeat checks that cannot affect the goal,
   scope, authority, constraints, or first action.
3. Report relevant non-blocking drift and continue. Stop for direction only when
   drift invalidates the goal, scope, authority, a constraint, or a required
   assumption.
4. Treat the handoff as the authorized task and follow the applicable repository
   workflow through completion, beginning with `Start Here`.

Never edit, move, annotate, archive, consume, or record status on the handoff.

## Content

Assume the receiver has zero conversation context. Prefer paths and symbols over
copied content or fragile line numbers.

```markdown
# Handoff: <goal>

## Goal

<One next-session operation and intended outcome.>

## Start Here

<One concrete first action after orientation.>

## Current State

<Only context, decisions, and state needed to continue.>

## Read

- `<authoritative path>` - <why it must be reloaded>

## Constraints

<Material scope exclusions, authority, safety, and behavioral invariants.>

## Done When

<Observable completion and relevant validation.>
```

Omit empty optional sections. Add `Blockers`, `Failed Approaches`, or
`Unverified` only when useful. Preserve exact user-provided technical text and
material uncertainty. Never include credentials, tokens, cookies, private keys,
`.env` values, personal details, or other secrets; name safe retrieval
instructions instead. Do not add lifecycle state, ancestry, progress tracking,
or execution records.
