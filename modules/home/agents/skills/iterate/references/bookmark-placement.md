# Bookmark Placement

Bookmark placement is orchestrator-owned. Run before creating a new iteration, replacing an
iteration with unrelated work, activating a planning state for new/replacement work, or dispatching
implement for an unrelated desired outcome. Do not run inside implement or verify. Do not run when
simply continuing an active iteration on its current bookmark.

Resolve placement with `jj-bookmark-current` and `jj-bookmark-default`.

- Current bookmark empty or default: stop before file edits, state activation, or worker dispatch.
  Ask for a bookmark name, create it with `jj bookmark create <name>`, then rerun the gate.
- Current bookmark non-default and requested work is the same logical change as current bookmark or
  iteration: continue.
- Current bookmark non-default and requested work is separable or relationship is unclear: ask
  whether to continue here or create a stacked bookmark.
- User chooses stacked bookmark: run `jj new`, then `jj bookmark create <name>`, before creating or
  activating iteration state and before normal iteration execution.
