# Herdr Core Terminals

When `HC_TERMINAL_ID` is set, you run inside herdr-core: run anything you would
otherwise background, or that takes more than a minute or two, as an `hc`
terminal the user can watch in the Herdr sidebar, whether it is a job, a server,
or another agent. Prefer it over your built-in subagent tool when the user would
want to see an agent's work, it runs long, or it may need steering; a quick
lookup can stay with the built-in tool. Outside herdr-core, use `hc` only when
the user asks. Read `hc --skill` before your first agent or remote work; where
it differs from this rule, follow this rule.

- Start a terminal with `hc run --bg --name <name> --cwd <dir> -- <command>`.
  For a job, add `--no-notify`, or hc types a note into your input when it ends.
  Do not use `--rm`: it removes a terminal that ends before you wait on it,
  along with its exit code.
- A terminal gets the login session's environment, not yours: write out values
  such as your `$TMPDIR` as absolute paths. When `<dir>` has an `.envrc`, run
  the project's commands through `direnv exec .`; if direnv reports the `.envrc`
  is blocked, ask the user to allow it rather than running `direnv allow`.
- Let a job write to its terminal, which keeps about 1,100 lines; for more, run
  `bash -c 'set -o pipefail; <command> 2>&1 | tee <log>'` with an absolute
  `<log>`. Never redirect output away from the terminal, which hides it, or
  append commands after the job, such as `; echo $?`, which replace its exit
  code. A job you would block on anyway can run in the foreground: leave out
  `--bg` and pass `--timeout`; `hc run` then exits with the job's code, or
  prints `[hc] still running as <t>` and exits 124, and then you wait on `<t>`.
- Pass `--timeout` below your shell tool's limit on every `hc wait`. It exits 0
  whatever happened, so read its JSON and wait again while `ended` is false.
  - A job: `ended` and `exit_code` give the result.
  - A server: `hc wait <name> --output <text>` ends with `reason` `output` when
    the text appears, while the server keeps running. It matches only output
    printed after the wait starts, so on a timeout `hc read` it for the text.
- Clean up what you started: `hc kill` a server when done and an agent once you
  accept its result, `hc read` any output you need, then `hc rm` it and any
  finished terminal it left in `hc ls --all`.

Start an agent in your own harness with
`hc run --bg --no-notify --label role=agent --name <name> --cwd <your working directory> -- <harness> "<task>"`,
with `claude` or `pi` as `<harness>`; opencode takes the task as
`opencode --prompt "<task>"`. Use these plain commands, not a sandboxed launcher
such as `nono-claude`, which cannot write to your temporary directory. Another
directory may stop it at a trust dialog.

- Before launching, create `$TMPDIR/hc-reports/` and choose a result path in it
  that no earlier agent used, such as `<name>-<unix time>.md`, written out with
  your own `$TMPDIR`. The task names that path and tells the agent to write its
  result, or what blocks it, there and then end its turn. If your own task names
  a result file, report only by writing it, never with `hc send`.
- Never `hc send` or `hc keys` to an agent you started: the text would join
  whatever the user is typing there. For more work, start a new agent whose task
  points at the earlier result file.
- Learn of your agents' news without anything typed into your input:
  - If your harness turns a command's output lines into notifications, such as
    Claude Code's Monitor tool, run `hc-child-watch` under it with the tool's
    longest timeout once you have started an agent. It prints
    `<address> <name> done`, `blocked`, or `error` when an agent ends a turn,
    waits on a prompt, or reports an error, and `<address> <name> exited <code>`
    when it ends. Run it again when it prints `watch-ended`, or when it prints
    `watch-failed` or the tool's timeout passes while an agent you started is
    live. While it runs, never run `hc wait --children`, which would take its
    wake-ups. You may end your turn while agents work. After two `watch-failed`
    lines in a row, or when it exits nonzero without one, tell the user and wait
    as below instead.
  - Otherwise wait with `hc wait --children any`. A `message` return means
    handle the waiting input first. After any other return, check each agent you
    started with `hc get`: one whose `status.state` left `working` with `turn`
    above 0, or whose `state` became `finished`, since you last handled it is
    news; otherwise wait again, as for a fresh agent's startup `idle`. When a
    turn starts while an agent is unfinished, check this way first.
- On news: when an agent ends a turn, read its result file, or `hc read` its
  screen when there is none. When it is `blocked`, tell the user what it asks;
  never answer its permission, trust, sign-in, or update prompt yourself. On an
  error or an exit, `hc read` its screen, unless you killed it yourself.
- Tell it to start no agents unless the user authorizes it in its own terminal.
  If you are such an agent, because your task says so, your instructions say
  another agent started you, or `PI_SUBAGENT=1` is set, you start none either.
