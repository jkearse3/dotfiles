# Rex Terminal

When `REX_SESSION` is set, you are running in a terminal pane of Rex, a terminal
multiplexer. `REX_SESSION` identifies your Rex session and `REX_BLOCK` your
pane. The user may be viewing a different session or pane, so pass
`-s "$REX_SESSION"` and `-b "$REX_BLOCK"` to target your own in `rex` commands.
These IDs are inherited and unchecked: if a target is not found, run
`rex whoami --json`. In the Rex CLI a tab is a window and a pane is a block.
Load the `rex` skill before any other Rex task.
