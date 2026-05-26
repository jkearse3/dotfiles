# Workflow

When a file-changing task is identified and no objective is loaded, present a concise prompt
offering these modes:

- **Direct**: investigate, present plan, get approval, edit. No objective, ACs, phases, or
  `/objective` commands.
- **Objective**: create or load an objective, then follow the `/objective` workflow (ACs, phases,
  iterate).

Non-editing tasks (questions, research, explanations) are exempt — no prompt needed.

**Skip the prompt when context already implies a mode:**

- An objective is already loaded → objective mode.
- The user explicitly invokes `/objective` → objective mode.

**On trunk**: ask for a bookmark name before file edits regardless of workflow mode.

**On a bookmark**: new work stacks on top of the current bookmark (stacked PRs). No need to return
to trunk first.

Full workflow details, format spec, and phase structure are in the `/objective` skill — invoke it
when executing any `/objective` command.
