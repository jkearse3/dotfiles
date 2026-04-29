# Workflow

When a file-changing task is identified and no goal is loaded, present a concise prompt offering
these modes:

- **Direct** — investigate, present plan, get approval, edit. No goal, ACs, phases, or `/goal`
  commands.
- **Goal** — create or load a goal, then follow the `/goal` workflow (ACs, phases, iterate).

Non-editing tasks (questions, research, explanations) are exempt — no prompt needed.

**Skip the prompt when context already implies a mode:**

- A goal is already loaded → goal mode.
- The user explicitly invokes `/goal` → goal mode.

**On trunk**: ask for a bookmark name before file edits regardless of workflow mode.

**On a bookmark**: new work stacks on top of the current bookmark (stacked PRs). No need to return
to trunk first.

Full workflow details, format spec, and phase structure are in the `/goal` skill — invoke it when
executing any `/goal` command.
