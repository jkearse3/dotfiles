# Workflow

On a file-changing task with no objective loaded, offer two modes (skip for non-editing tasks —
questions, research, explanations):

- **Direct**: bounded tasks without objective ceremony. Scale investigation, planning, and
  verification to the task's risk and ambiguity. Explicit approval before editing is required.
- **Objective**: create or load an objective, then follow the `/objective` workflow (ACs, phases,
  iterate).

Direct mode uses only the steps needed:

- Investigate when the right change is not already clear.
- Plan when there are meaningful choices, multiple files, or behavioral risk.
- Ask for explicit approval before editing.
- Edit after approval.
- Verify when there is a cheap relevant check.
- Summarize the change and any verification gaps.

For trivial edits, Direct can be as small as: state the intended edit → approval → edit → summarize.

Use Objective for ambiguous, risky, multi-phase, or acceptance-criteria-driven work.

Skip the prompt when context implies a mode: an objective is already loaded, or the user invokes
`/objective` → objective mode.

VCS placement:

- **On trunk**: ask for a bookmark name before any file edits, regardless of mode.
- **On a bookmark**: stack new work on top (stacked PRs); no need to return to trunk first.

Full workflow details, format spec, and phase structure live in the `/objective` skill — invoke it
for any `/objective` command.
