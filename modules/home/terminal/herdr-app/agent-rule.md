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
`hc run --bg --no-notify --label role=agent --name <stem> --cwd <your working directory> -- <harness command>`.
`<stem>` is `<name>-<unix time>`, with `<name>` at most 21 characters of `a-z`,
`0-9`, and `-`; it names the terminal and the agent's session. Use these plain
harness commands, not a sandboxed launcher such as `nono-claude`, which cannot
write to your temporary directory:

```text
claude    start:  claude --name <stem> "<task>"
          resume: claude --resume <stem> "<follow-up>"
pi        start:  pi --session-id <stem> --name <stem> "<task>"
          resume: pi --session-id <stem> "<follow-up>"
opencode  start and resume: opencode --session ses_<stem> --prompt "<task>"
```

Another directory may stop it at a trust dialog.

- Before each launch, first or resumed, create `$TMPDIR/hc-reports/` and give
  that launch its own result path, `<stem>-<unix time>.md` in it, written out
  with your own `$TMPDIR`. The task names that path and tells the agent to write
  its result, or what blocks it, there and then end its turn. If your own task
  names a result file, report only by writing it, never with `hc send`.
- Never `hc send` or `hc keys` to an agent you started: the text would join
  whatever the user is typing there. For more work, start a new agent or resume
  an earlier one:
  - Resume when the work continues the agent's own task and its context helps:
    answering a question or blocker it wrote to its result file, fixing or
    extending its own output, or digging further into what it investigated. A
    `blocked` agent is waiting on a prompt that goes to the user, never one you
    answer by resuming it.
  - Start a new agent for a different task; for independent judgment, such as
    reviewing what an earlier agent produced; when the earlier session went down
    a wrong path; or when another harness, model, or directory is needed. When
    unsure, start a new one whose task points at the earlier result file.
  - To resume, `hc kill` the earlier terminal if it is live and `hc rm` it, then
    launch the resume form with the same stem and the first launch's `--cwd`,
    since pi and opencode look sessions up per directory and start an empty one
    on a miss. The follow-up names its new result path, says not to write to the
    earlier one, and tells the agent to write `no earlier context` there and
    stop if it does not recognize its earlier task.
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
