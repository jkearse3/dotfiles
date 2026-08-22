---
name: notes
description: >-
  Create, find, or read durable local notes the user wants to revisit later:
  architecture docs, decision rationale, findings, and other parked knowledge.
  Use when the user asks to leave or jot a note, drop a doc in the notebook, or
  come back to a prior note. Not for capturing something the user did not ask to
  keep.
argument-hint: "[note topic, or find/read <topic>]"
---

# Notes

Keep durable, revisitable knowledge in an ignored local notebook. A note is an
ordinary Markdown file under `.agent/notes/`, not workflow state, execution
authority, or an approval record.

Notes hold unstructured knowledge worth keeping: architecture and design
write-ups, decision rationale, findings parked for later, context you want to
return to. They carry no schema and no lifecycle. A note records knowledge to
revisit — not work to execute, not a task to resume elsewhere, and not a
question answered inline. Write one only when the user asks to keep something.

## Arguments

```text
$ARGUMENTS
```

Interpret `$ARGUMENTS` and recent conversation as natural language:

- Create by default when the user asks to leave, jot, write, or save a note or
  document. Infer the topic from the request and conversation.
- Find or read when the user asks what notes exist, or to open, recall, or come
  back to a prior note.
- An explicit request to show, list, or edit a note authorizes only that
  ordinary file operation.

Writing a note is only authorized when the user asks for one. Do not silently
persist a note as a side effect of other work.

## Create

1. Choose a concise lowercase kebab-case slug for the topic. Run
   `scripts/prepare-path.sh --workspace <target-repo> <slug>`, passing the
   absolute path of the repository you are working in as `<target-repo>`. Invoke
   the script by its path; it is independent of the current working directory
   and never derives the target from where it runs. It resolves canonical
   storage, safely prepares the ignored store, atomically reserves a new dated
   note file, and prints its absolute path. If it reports ambiguous storage or a
   safety failure, stop and report that error rather than bypassing it.
2. Write the note to that path using the structure below. Draw on the
   conversation and inspect only a path or claim whose correctness is genuinely
   uncertain; mark other uncertainty explicitly rather than reconstructing the
   repository.
3. Report the absolute path.

Creating the local store and note is the full authorized mutation. Do not
perform described follow-on work or modify revision history.

## Find And Read

Resolve the store root with
`scripts/resolve-store.sh --workspace <target-repo>`, passing the absolute path
of the repository you are working in as `<target-repo>`. Invoke the script by
its path; it is independent of the current working directory. Notes live
directly under `<root>/.agent/notes/` as dated Markdown files.

List the store when the user asks what notes exist. To open a specific note,
match its dated filename and slug against the request; the slug and date carry
the topic, so infer intent from filenames without reading every note. When
exactly one note is clearly intended, read it. If several remain plausible, list
the candidates and ask which one rather than guessing.

## Content

Notes are unstructured by design. Keep only what makes the note useful when the
user returns to it cold, and prefer stable paths and symbols over copied content
or fragile line numbers. The heading and a short orienting line are the only
fixed parts; add whatever sections the material warrants.

```markdown
# <Note title>

<One line on what this note is and why it was kept.>

<Body: whatever the note needs — prose, decisions and their rationale, diagrams,
references, open questions. No required sections.>
```

## Boundaries

- Without an explicit request to write a note, this skill is read-only.
- Keep `.agent/notes/` entirely ignored and untracked. Never treat it as a task
  registry or add progress, completion, ownership, approval, or lifecycle state.
  The only authorized mutations are notes below `.agent/notes/` and safe
  creation of that ignored store.
- Do not edit, move, rename, archive, or delete an existing note unless the user
  asks. Notes are the user's durable record; leave prior notes intact.
- Never include credentials, tokens, private keys, `.env` values, or other
  secrets; name safe retrieval instructions instead.
