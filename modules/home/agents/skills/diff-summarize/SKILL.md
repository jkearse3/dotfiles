---
name: diff-summarize
description: Summarizes code changes for a revision, commit, jj change ID, bookmark, branch, PR, diff command, or working tree; use when the user asks for a summary of changes.
argument-hint: "branch changes | working changes | jj diff --from main | revision <rev>"
---

# Diff Summarize

Analyze code changes and produce a structured technical summary.

## Input

```
$ARGUMENTS
```

The input is free-form natural language. Interpret it to determine:

1. **What to summarize** — a literal diff command, a description of what to summarize, or both. If
   the input contains a runnable diff command, use it directly. If it describes what to summarize
   (`branch changes`, `working changes`, `PR #42`, `the last 3 commits`, a bookmark, or a specific
   revision), determine the appropriate diff command. If the intent is clear but the exact diff
   cannot be determined, ask for clarification rather than guessing.
2. **Output purpose** — PR description, branch handoff, quick technical summary, or other context
   included in the input. Use this context to tune wording, but keep the output technical.

If the input is empty or does not make the diff target clear, ask for clarification with examples:

```
What changes should I summarize?

Examples:
  summarize branch changes
  summarize working changes
  jj diff --from main --to @
  summarize PR #42 for a PR description
  summarize the last 3 commits
```

## Execution

1. **Determine diff command**. Use the input to determine the diff command. If the input described
   what to summarize rather than providing a literal command, determine the appropriate command now.
   If the command cannot be determined confidently, ask for clarification and stop.

2. **Determine overview and per-file commands**. From the selected diff target, determine:
   - An overview command that lists changed files, such as the selected diff command with `--stat`
   - A per-file command that isolates one changed file, such as the selected diff command with
     `--git <file>`

3. **Get diff overview**. Run the selected overview command. If the command fails, report the error
   and stop.

   If no changes are found, return:

   ```markdown
   ## Result: Diff Summary

   ### Summary Target
   <what was summarized>

   ### Review Scope
   No changes found.

   ### Overview
   No changes found.

   ### Changes
   None
   ```

4. **Analyze changed files and groups**. Start from the overview to make an initial grouping plan
   based on paths, file status, and change size. Treat that plan as a hypothesis, not proof.

   Inspect files individually when they contain distinct behavior, configuration, schemas,
   migrations, tests, CI/deployment changes, dependency semantics, or other changes that need their
   own explanation.

   Group files when they appear mechanical or repetitive, such as generated files, vendored files,
   lockfiles, snapshots, fixtures, rename-only changes, formatting-only changes, or repeated updates
   with the same purpose.

   Before summarizing a group, inspect enough diffs to confirm that the files share the same
   purpose, change pattern, and risk profile. If the pattern is unclear, inspect the file
   individually instead of grouping it. For individually summarized files, run the selected per-file
   diff command and read full file context when needed.

5. **Analyze the overall change**. After reviewing the changed files, write a concise overview of
   the diff as a whole. The overview should briefly describe the technical shape of the change
   without duplicating the file-by-file entries. Do not write commit-message rationale; reserve
   durable intent, motivation, and risk framing for commit messages.

6. **Return result**. Return the structured result exactly:

   ```markdown
   ## Result: Diff Summary

   ### Summary Target
   <what was summarized>

   ### Review Scope
   <how the diff was inspected, including whether files were reviewed individually or grouped>

   ### Overview
   <brief technical summary of the overall diff>

   ### Changes
   - **path/to/file.ext**: What the file does. What changed.
   - **another/file.ext**: File purpose. Specific modifications.
   - **related/files/**/*.ext**: Shared purpose for this group. Common change across these files.
   - **generated files (`api/**/*.pb.go`, 14 files)**: Generated API bindings. Grouped because the
     changes are mechanical outputs from the schema update.
   ```

Guidelines:

- Use a concrete summary target, such as `branch changes against main` or
  `jj diff --from main --to @`, not a vague restatement of the user prompt
- Include a short `Review Scope` that states how the diff was inspected. For small diffs, say that
  all changed files were reviewed individually. For larger diffs, mention important files reviewed
  individually and repeated or mechanical changes grouped after confirming their pattern.
- Include a short `Overview` that summarizes the diff holistically. Keep it technical and factual;
  do not duplicate commit-message rationale.
- Keep each entry concise, usually 1-2 sentences
- State the file or group's role, then what changed
- Focus on technical changes; mention user-facing impact only when it explains the change
- Group related files when they changed for the same reason and a per-file summary would be
  repetitive
- Do not group files with distinct behavior, risk, or review concerns
- For generated, vendored, lockfile, snapshot, or mechanical changes, prefer one grouped entry that
  names the pattern and states why the files are grouped
