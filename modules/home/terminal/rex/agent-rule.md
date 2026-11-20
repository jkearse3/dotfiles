# Rex Terminal

When `REX_SESSION` is set, you are running in a pane of Rex, a terminal
multiplexer: `REX_SESSION` names your Rex session and `REX_BLOCK` your pane. The
user may be viewing another session or pane, so pass `-s "$REX_SESSION"` and
`-b "$REX_BLOCK"` to `rex` commands to target your own. Both values are
inherited from the shell that started you and can be stale; if Rex reports a
target not found, run `rex whoami --json` for the current ones. The Rex CLI
calls a tab a window and a pane a block. Load the `rex` skill before any other
Rex task.
