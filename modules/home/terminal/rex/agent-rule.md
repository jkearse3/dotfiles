# Rex Terminal

When `REX_BLOCK` is set and `HC_TERMINAL_ID` is not, you run in a Rex pane and
the Agent Terminals rule's terminals are Rex tabs.

- Start an agent with
  `rex-agents start <name> --harness <your harness> --task <task>`, adding
  `-C <dir>` for another directory; `--task -` reads the task from standard
  input. It picks the stem and result path, appends the report and no-agents
  instructions to the task, opens the agent's tab, and prints the agent's `name`
  (its stem), `block`, and `result` path as JSON. Resume an agent with
  `rex-agents resume <stem> --task <follow-up>`, which carries out the resume
  steps and refuses an agent that is still starting, working, or blocked.
- Once you accept an agent's result, `rex-agents release <stem>` closes its
  pane.
- The child watcher is `rex-agents watch`; its `<terminal>` is the agent's block
  ID and its `<name>` the stem. The waiting path is
  `rex-agents watch --until-news --timeout <seconds>`. Keep the timeout at 60
  seconds or less, because the watcher cannot notice the user's messages. When a
  turn starts while an agent is unfinished, run it with `--timeout 0` first. It
  exits 0 without a line once none of your agents is live. When the watcher
  keeps failing, `rex-agents ls` shows each agent's state.
- For jobs and servers, load the `rex` skill and use its guide's commands. Open
  each as its own tab with `--keep-open` and `--focus=false`: without
  `--keep-open`, a pane closes when its program exits and takes the exit code
  with it. Write the full block ID out in each command rather than keeping it in
  a shell variable: an empty `-b` selects your own pane.
