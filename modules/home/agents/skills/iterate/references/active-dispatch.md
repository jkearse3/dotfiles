# Worker Dispatch

Implement and verify are subagent-only.

Each dispatch includes:

- Absolute state file path.
- Absolute workspace root.
- Matching worker brief file path.
- Instruction to read the matching brief file directly from disk and follow it.

Implement and verify dispatches also instruct the worker to read and update the state file.

Before dispatch, resolve the referenced bundled resource to the matching brief file path under
`briefs/`. Pass that path in the worker prompt; do not inline full brief contents, summaries,
excerpts, source-tree paths, or alternate brief files.

Active implement/verify worker subagent unavailable, failed, returned without state-file progress,
changed out of bounds, changed revision lifecycle, or violated its role: record a concrete `[!]`
issue, set `Status: blocked`, set `Next: none`, and stop.

State-file progress:

- Implement: control fields, research, approach, task markers, direct blockers, candidate
  verification notes, or context. AC markers, AC evidence, and normal issue lifecycle are not
  implementation progress.
- Verify: control fields, AC markers or evidence, issue markers, research, assumptions, or context.

Repo edits without a state-file update are not durable iteration progress. After each active
subagent returns, ignore its summary for routing; reread the state file and route only from
`Status:` / `Next:`.
