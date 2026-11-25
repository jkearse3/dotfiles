# Herdr Core Terminals

When `HC_TERMINAL_ID` is set, you run inside herdr-core, and the Agent Terminals
rule's terminals are `hc` terminals, which the user watches in the Herdr
sidebar. Read `hc --skill` before your first agent or remote work; where it
differs from these rules, follow these rules.

- Start a terminal with `hc run --bg --name <name> --cwd <dir> -- <command>`.
  For a job, add `--no-notify`, or hc types a note into your input when it ends.
  Do not use `--rm`: it removes a terminal that ends before you wait on it,
  along with its exit code.
- A terminal keeps about 1,100 lines. A job you would block on anyway can run in
  the foreground: leave out `--bg` and pass `--timeout`; `hc run` then exits
  with the job's code, or prints `[hc] still running as <t>` and exits 124, and
  then you wait on `<t>`.
- Pass `--timeout` below your shell tool's limit on every `hc wait`. It exits 0
  whatever happened, so read its JSON and wait again while `ended` is false.
  - A job: `ended` and `exit_code` give the result.
  - A server: `hc wait <name> --output <text>` ends with `reason` `output` when
    the text appears, while the server keeps running. It matches only output
    printed after the wait starts, so on a timeout `hc read` it for the text.
- Read a terminal's screen with `hc read`. To clean up, `hc kill` a server or
  agent, `hc read` any output you need, then `hc rm` it and any finished
  terminal it left in `hc ls --all`.
- Start an agent with
  `hc run --bg --no-notify --label role=agent --name <stem> --cwd <your working directory> -- <harness command>`.
  Never `hc send` or `hc keys` to it. To resume one, `hc kill` the earlier
  terminal if it is live and `hc rm` it first.
- The child watcher is `hc-child-watch`, whose `<terminal>` is the agent's hc
  address. While it runs, never run `hc wait --children`, which would take its
  wake-ups.
- The waiting path is `hc wait --children any`. A `message` return means handle
  the waiting input first. After any other return, check each agent you started
  with `hc get`: one whose `status.state` left `working` with `turn` above 0, or
  whose `state` became `finished`, since you last handled it is news; otherwise
  wait again, as for a fresh agent's startup `idle`. When a turn starts while an
  agent is unfinished, check this way first.
