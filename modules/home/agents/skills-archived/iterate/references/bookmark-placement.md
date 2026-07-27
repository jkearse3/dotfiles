# Bookmark Placement

Bookmark placement is procedure-owned. Run before creating a new iteration,
replacing an iteration with unrelated work, activating a planning state for
new/replacement work, or running implement for an unrelated desired outcome. Do
not run inside implement or verify. Do not run when simply continuing an active
iteration on its current bookmark.

Resolve placement with `jj-bookmark-current` and `jj-bookmark-default`.

- Current bookmark empty or default: stop before file edits, state activation,
  or implementation. Ask for a bookmark name, create it with
  `jj bookmark create <name>`, then rerun the gate.
- Current bookmark non-default and requested work is the same logical change as
  current bookmark or iteration: continue.
- Current bookmark non-default and requested work is separable or relationship
  is unclear: ask whether to continue here or create a stacked bookmark.
- User chooses stacked bookmark: create the bookmark on the existing empty `@`
  revision. If `@` is not empty, run `jj new` first, then create the bookmark.
  Do this before creating or activating iteration state and before normal
  iteration execution.
