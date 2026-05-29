# Workflow

On a file-changing task with no objective loaded, offer two modes (skip for non-editing tasks —
questions, research, explanations):

- **Direct**: investigate → plan → approval → edit. No objective, ACs, or phases.
- **Objective**: create or load an objective, then follow the `/objective` workflow (ACs, phases,
  iterate).

Skip the prompt when context implies a mode: an objective is already loaded, or the user invokes
`/objective` → objective mode.

VCS placement:

- **On trunk**: ask for a bookmark name before any file edits, regardless of mode.
- **On a bookmark**: stack new work on top (stacked PRs); no need to return to trunk first.

Full workflow details, format spec, and phase structure live in the `/objective` skill — invoke it
for any `/objective` command.
