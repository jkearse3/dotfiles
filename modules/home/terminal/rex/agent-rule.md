# Rex Terminal

When `REX_BLOCK` is set and `HC_TERMINAL_ID` is not, you run in a Rex pane and
the Agent Terminals rule's terminals are Rex panes. Load the `rex` skill and use
its guide's commands for each step, with these differences:

- Open each terminal as its own tab with `--keep-open` and `--focus=false`.
  Without `--keep-open`, a pane closes when its program exits and takes the exit
  code with it.
- Write the full block ID out in each command rather than keeping it in a shell
  variable: an empty `-b` selects your own pane.
- The child watcher is `rex-child-watch`. Rex does not link a pane to the one
  that started it, so register each agent by passing its block ID to the next
  `rex-child-watch` run you start, under your notification tool or on the
  waiting path. When a watcher already runs for you, that run hands it the
  block, prints `watch-already-running`, and ends. Pass no block on later runs.
- The waiting path is `rex-child-watch --until-news --timeout <seconds>`. Keep
  the timeout at 60 seconds or less, because the watcher cannot notice the
  user's messages. When a turn starts while an agent is unfinished, run it with
  `--timeout 0` first. It exits 0 without a line once none of the agents you
  registered is live. When the watcher keeps failing, check each agent with
  `rex block call -b <block> program_status` and `process`: a status that left
  `working`, or a `last_exit`, is news.
