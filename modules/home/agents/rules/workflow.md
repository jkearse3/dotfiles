# Workflow

For repo-changing work, choose the smallest workflow that safely fits the task. Skip workflow
selection for non-editing tasks: questions, research, explanations.

Use increasing ceremony only when the task needs it:

- **Direct**: trivial or tightly bounded changes. Scale investigation, planning, and verification to
  the task's risk and ambiguity. Explicit approval before editing is required.
- **Iterate**: nontrivial, ambiguous, multi-step, or verification-sensitive repo changes. Draft
  `.agent/iterate.md` as a plan, get explicit user approval, then follow the `iterate` workflow
  until it reaches review or blocks.
- **Objective**: broad, high-ceremony, acceptance-criteria-driven work. Create or load an objective,
  then follow the `/objective` workflow.

Direct uses only the steps needed:

- Investigate when the right change is not already clear.
- Plan when there are meaningful choices, multiple files, or behavioral risk.
- Ask for explicit approval before editing.
- Edit after approval.
- Verify when there is a cheap relevant check.
- Summarize the change and any verification gaps.

For trivial edits, Direct can be as small as: state the intended edit → approval → edit → summarize.

Skip selection when context implies the workflow: an iterate loop exists, an objective is loaded,
the user invokes `/objective`, or the user explicitly asks for Direct, Iterate, or Objective.

VCS placement:

- **On trunk**: ask for a bookmark name before any file edits, regardless of workflow.
- **On a bookmark**: stack new work on top (stacked PRs); no need to return to trunk first.

Full workflow details, format spec, and phase structure live in the `/objective` skill — invoke it
for any `/objective` command.
