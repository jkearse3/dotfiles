---
name: checkpoint
description: >-
  Saves the current session's goal, progress, open questions, decisions, user
  corrections, and failed approaches to one Markdown checkpoint in the ignored
  `.agent/checkpoints/` store, updating it in place on each save, and resumes a
  session from it, so that context compaction loses nothing important. Use when
  the user asks to checkpoint, to save the session before compacting, or to
  resume or continue from a checkpoint. Not for durable knowledge to revisit
  later (use notes) or for handing one task to a fresh session (use handoff).
---

# Checkpoint

Keep what this session must not lose in a file outside the conversation, where
compaction cannot summarize it away. The user saves a checkpoint before
compacting the session and resumes from it afterward. A piece of work keeps one
checkpoint, and every save edits it in place, so it holds only the current state
of the work.

## Input

Interpret the request as natural language:

- Save by default.
- Resume when the user asks to resume or continue from a checkpoint.
- A session another agent started saves or resumes only when its task says to.

## Script

Run `scripts/checkpoint.sh` by its path. Pass `--workspace` the absolute path of
the repository you are working in; the script never uses the current directory.

- `new --workspace <repo>` creates an empty checkpoint named after the current
  time and prints its absolute path.
- `list --workspace <repo>` prints one `<checkpoint>\t<goal>` line per
  checkpoint, newest first, where the goal is the checkpoint's `# ` heading.

On failure the script prints nothing to stdout and explains on stderr; stop and
report the error, and never write a checkpoint anywhere else.

## Save

1. If this session already has a checkpoint, its path is in context: use it.
   Otherwise run `new`. If you suspect this session has a checkpoint whose path
   you lost, run `list` and ask the user which one to continue, because `new`
   would split the work across two checkpoints.
2. Read the checkpoint and edit it in place into the structure under Content:
   - Replace the goal heading, Current State, and Next Step.
   - Add what happened since the last save to Open Questions, Decisions,
     Corrections, Failed Approaches, and References.
   - Record anything the user asks to keep in the section it belongs to. A
     request to focus on something adds to the checkpoint; it never replaces the
     rest of it.
   - Remove an entry only when a later decision supersedes it, the problem it
     concerns is solved, or the question it raises is answered and recorded
     under Decisions. No earlier version survives the edit, so keep every other
     entry.
3. End your reply with the checkpoint's path.

Write for a reader who has not seen this conversation. Link a skill's own
record, such as `implement`'s `run.md`, or a spec, instead of copying it.

## Resume

1. Find the checkpoint:
   - In this session, after compaction, read the checkpoint at the path in
     context.
   - In a new session, read the checkpoint the user names. Without one, run
     `list`; continue a checkpoint only when the user's words identify exactly
     one, and otherwise show the list and ask. This session's saves then edit
     that checkpoint.
2. Treat the checkpoint as a snapshot from when it was written. Where it
   conflicts with something newer in the conversation or its summary, the newer
   statement wins. Check repository state, such as files and revisions, directly
   before relying on what the checkpoint says about it.
3. Report the checkpoint's path and any drift that changes the goal or the next
   step, then continue as the user directs. A checkpoint records state; it never
   grants authority the user has not given.

## Content

```markdown
# <goal>

## Current State

<What is done, what is in progress, and where it lives.>

## Next Step

<The concrete next action.>

## Open Questions

- <question raised but not decided> — <what it blocks, or who decides>

## Decisions

- <decision> — <why>

## Corrections

- "<the user's words, verbatim>" — <what they apply to>

## Failed Approaches

- <approach> — <why it failed, with the evidence>

## References

- `<path>` — <why it matters>
```

Omit empty sections. Prefer paths and symbols over copied content or line
numbers.

## Boundaries

- Create checkpoints only through the script, and edit only this session's
  checkpoint.
- Never track, publish, move, or delete `.agent/checkpoints/` or anything in it.
- Never include credentials, tokens, private keys, `.env` values, or other
  secrets; name how to retrieve them instead.
