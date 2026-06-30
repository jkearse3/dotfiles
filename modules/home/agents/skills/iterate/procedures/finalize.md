# Finalization

Use only for `Status: complete` with `Next: finalize`.

Finalization is orchestrator-owned and runs only after user acceptance, explicit closure, or
otherwise reaching `Status: complete`. Closeout mutations require explicit approval for the current
finalization candidate. That approval may come from review when review just displayed the current
candidate and routed here in the same invocation, or from an explicit finalization approval in the
current invocation.

Before any closeout mutation, reread `.agent/iterate.md`, validate its `## Finalization Candidate`
section, and confirm the user explicitly approved closeout for the current candidate. If the current
candidate has not been displayed before requesting approval, or if closeout approval is missing or
unclear, summarize the candidate, ask for explicit closeout approval, and stop. Do not run any VCS
lifecycle action.

All candidates:

- The section must exist exactly once.
- It must contain `closeout`.
- `closeout` must be `none` or `finalize-revision`.

For `closeout: none`:

- The section must contain only `closeout`.
- No VCS lifecycle action is authorized. Update `.agent/iterate.md` to `Status: finalized`,
  `Next: none`, then stop and respond using the runbook's stopped-iteration response rules.

For `closeout: finalize-revision`:

- The section must contain only `closeout`, `target_commit`, and `revision_description`.
- `target_commit` must be non-empty and must exactly match the current `@` commit id from read-only
  jj inspection:

  ```sh
  jj log -r @ --no-graph -T 'commit_id ++ "\n"'
  ```

- `revision_description` must be a non-empty complete jj revision description in its fenced `text`
  block.

If the candidate is missing, duplicated, malformed, contains any other metadata for its closeout
mode, was not displayed before approval was requested, was not explicitly approved for closeout, or
if current `@` does not match `target_commit` for `finalize-revision`, stop and ask for direction.
Do not split automatically, describe the target, or run `jj new`.

For `closeout: finalize-revision`, assign the persisted `revision_description` to a shell variable
exactly as extracted from the state file and validate that exact value with `commit-message-check`.
If validation fails, stop with the checker output. Do not edit the description during finalization
unless the user sends the workflow back through implement or verify.

After candidate validation and message validation both pass, run `jj describe -r @ -m "$desc"`, then
run `jj new` so the workspace ends on a fresh revision. After both commands complete, update
`.agent/iterate.md` to `Status: finalized`, `Next: none` so future resumes do not operate on the
archived iteration, then stop and respond using the runbook's stopped-iteration response rules.
