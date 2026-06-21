# Reconcile Worker Dispatch

Reconciliation is worker/subagent-only. The orchestrator must not run the heavy reconciliation flow
inline.

Before dispatch, resolve these absolute paths:

- Workspace root.
- Markdown contract path.
- Sidecar state path.
- Bundled helper script path.
- Bundled reconciliation worker brief path at `briefs/reconcile.md`.

Each dispatch includes:

- The absolute workspace root.
- The absolute Markdown contract path.
- The absolute sidecar state path.
- The absolute helper script path.
- The absolute reconciliation worker brief path.
- An instruction to read the brief directly from disk and follow it.

Do not inline full brief contents, summaries, excerpts, source-tree paths, or alternate brief files
in the dispatch prompt. The worker receives paths, not copied instructions.

The dispatch contract is host-agnostic. Do not require OpenCode command config, Claude frontmatter,
named agents, MCP servers, plugins, or any other agent-specific configuration. If the current host
has no worker/subagent dispatch mechanism, stop with a diagnostic instead of reconciling inline.

After dispatch returns, treat the worker summary as advisory. Reread durable state from the Markdown
contract and sidecar helper before reporting results.
