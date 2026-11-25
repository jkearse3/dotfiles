# Rex Terminal

When `REX_SESSION` is set, you are running in a pane of Rex, a terminal
multiplexer: `REX_SESSION` names your Rex session and `REX_BLOCK` your pane. The
user may be viewing another session or pane, so pass `-s "$REX_SESSION"` and
`-b "$REX_BLOCK"` to `rex` commands to target your own. Both values are
inherited from the shell that started you and can be stale; if Rex reports a
target not found, run `rex whoami --json` for the current ones. The Rex CLI
calls a tab a window and a pane a block. Load the `rex` skill before any other
Rex task.

When `REX_SESSION` is set and `HC_TERMINAL_ID` is not, the Agent Terminals
rule's terminals are Rex panes, each in its own tab of your session. Where the
`rex` skill's guide differs from these rules, follow these rules.

- Start a terminal with
  `rex window new -s "$REX_SESSION" <name> -c <dir> --keep-open --focus=false --json -- <command>`.
  Always pass `--keep-open`: a pane that closes when its program exits takes the
  exit code with it.
- Name the terminal afterwards by the full block ID the command prints as
  `.block_ids[0]`, such as `block:01a2…`, written out in each command rather
  than kept in a shell variable: an empty `-b` selects your own pane. Leave out
  `-s` when you name a block, so a tab the user moved to another session is
  still found.
- A terminal keeps about 100,000 lines.
- Wait on a job with
  `rex wait <block> --for <seconds below your shell tool's limit>s --json`. It
  exits with the job's code and prints `{"exit_code":N}`. Without that JSON,
  check `rex block call -b <block> process`: `last_exit` gives the result, a
  not-found error means the pane was closed, and otherwise wait again.
- A server is ready when `rex capture` shows its startup line.
- Read a terminal's screen with `rex capture -b <block> --trim | tail -n 200`,
  widening the tail as needed; an agent reported `exited closed` has no screen
  left. Stop a job or server with `rex send-key -b <block> ctrl+c`. Remove any
  terminal, an agent's too, with `rex block close <block>`, which ends what
  still runs there.
- Start an agent with the same command, `<stem>` as `<name>`, and your working
  directory as `<dir>`. Never `rex send` or `rex send-key` to it. To resume one,
  `rex block close` the earlier terminal first.
- The child watcher is `rex-child-watch`, whose `<terminal>` is the agent's
  block ID. Rex does not link a pane to the one that started it, so after each
  agent start, run `rex-child-watch <block>` to register it. Under a
  notification tool, run it with the tool's longest timeout; when a watcher
  already runs for you, the new one hands it the block, prints
  `watch-already-running`, and ends. Pass no block when you run it again.
- The waiting path is
  `rex-child-watch --until-news --timeout <at most 60, and below your shell tool's limit> <block>`
  for a newly started agent, repeated without the block while an agent is
  unfinished. It cannot notice the user's messages, hence the 60-second cap.
  When a turn starts while an agent is unfinished, run it with `--timeout 0`
  first. It exits 0 without a line once none of the agents you registered is
  live. When the watcher keeps failing, check each agent with
  `rex block call -b <block> program_status` and `process`: a status that left
  `working`, or a `last_exit`, is news.
