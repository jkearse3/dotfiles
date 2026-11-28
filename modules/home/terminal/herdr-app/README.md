# Known `hc` behavior

The Agent Terminals rule `modules/home/terminal/agent-terminals.md` and the
herdr-core rule `modules/home/terminal/herdr-app/agent-rule.md` work around the
behavior below, observed with `hc 0.1.21` and the agents it starts. Some of it
contradicts the upstream `hc --skill` guide. After an update, rerun the
reproductions and drop the rules' matching instruction for anything that no
longer holds.

## `--bg --rm` loses a fast job's exit code

`hc run --help` says `--rm` removes a terminal "once a waiting parent has the
exit code", and the `hc --skill` examples pair `hc run --bg --rm` with
`hc wait`. When the job exits before `hc wait` starts, the core has already
removed it, so the wait finds nothing:

```console
$ hc run --bg --rm --no-notify --name demo -- bash -c 'exit 3'
$ hc wait demo
{"error":{"kind":"not_found","message":"no terminal \"demo\"",...}}
```

A job that runs for a few seconds is waited on normally. A foreground
`hc run --rm` whose own wait times out has the same race: if the job ends before
the follow-up `hc wait`, that wait returns `not_found`. The rule therefore never
uses `--rm` and removes each terminal with `hc rm` once it has ended.

## A foreground run notifies its caller unless told not to

Without `--no-notify`, a finished `hc run` types a note such as
`t3x exp-fg6 exited (exit 6). Read: hc read t3x` into its parent terminal's
input, which reaches an agent as a new message, even when the run was in the
foreground and already reported the exit code.

## `hc wait` exits 0 whatever the job returned

`hc wait` reports the job's result only in its JSON. It exits 0 when the job
fails and when its timeout passes first:

```console
$ hc run --bg --no-notify --name demo -- bash -c 'exit 4'
$ hc wait demo; echo "rc=$?"
{"ended":true,"exit_code":4,"reason":"exit",...}
rc=0
$ hc run --bg --no-notify --name slow -- bash -c 'sleep 6'
$ hc wait slow --timeout 2; echo "rc=$?"
{"ended":false,"exit_code":null,"reason":"timeout",...}
rc=0
```

A foreground `hc run` does exit with the job's code, unless its own wait times
out (after `--timeout` seconds, 180 by default), in which case it prints
`[hc] still running as <t>` and exits 124.

## `hc wait --output` misses earlier output and does not mean the job ended

`hc wait <t> --output <text>` ends with `"ended":true` and `"reason":"output"`
when the text appears, while the job keeps running. It matches only output
printed after the wait started, so text the job printed before then makes the
wait run to its timeout:

```console
$ hc run --bg --no-notify --name srv -- bash -c 'echo ready; sleep 300'
$ sleep 1; hc wait srv --output ready --timeout 4
{"ended":false,"exit_code":null,"reason":"timeout",...}
```

`hc rm` removes only a finished terminal, so a server stays until `hc kill <t>`
ends it.

## A terminal keeps about 1,100 lines

`hc read <t> --lines 300000` after `seq 1 200000` returns about 1,120 lines and
warns `[hc] incomplete: older output may be missing`. Lines 200 characters wide
give the same count, so the limit is in lines.

## Jobs get the login environment, not the caller's

A terminal started with `hc run` gets the login session's environment. Inside
it, `$TMPDIR` is the login session's (`/var/folders/.../T/`) rather than the
agent's private one, and a project's direnv shell is not loaded, so tools such
as `pnpm` from a flake devshell are missing. `--cwd` is honoured, and
`direnv exec .` inside the job loads the devshell.

## Removing a terminal leaves its children

`hc rm` on a parent terminal removes only that terminal; its finished children
stay listed in `hc ls --all` until each is removed.

## Typed text joins a person's unfinished draft

`hc send` pastes text and presses Enter, and so do the notes hc types into a
parent. hc holds either while a person types, but only up to `draft_wait`
seconds (60 by default) after their last key. After that the paste lands after
whatever the person left in the input box, and Enter submits both as one prompt.
Keys sent with `hc keys` do not count as a person typing, so they reproduce the
result without waiting out the hold:

```console
$ hc run --bg --no-notify --name drafttest -- claude
$ hc keys drafttest h a l f space t y p e d space d r a f t
$ hc send drafttest '<hc from="t9 probe">CHILD REPORT</hc>'
```

The agent received the single prompt
`half typed draft<hc from="t4b"><hc from="t9 probe">CHILD REPORT</hc></hc>`. The
rule therefore launches agents with `--no-notify` and never sends to one.

## An agent started with its task as an argument can report startup `idle`

`hc wait --help` says that "Without a launch task, idle still counts as
stopped", and hc knows of a launch task only when a template starts the agent.
An agent started as `hc run --bg --name <name> -- claude "<task>"` can report
`idle` before its task begins, and a wait returns on it:

```console
$ hc run --bg --name evchild2 -- claude "<task>"
$ hc wait evchild2 --timeout 60
{"ended":true,"reason":"status","status":"idle",...}
```

The next wait returned `working`. The rule and `hc-child-watch` ignore a status
while `turn` is still 0.

## `hc wait --children any` misses turns that end while no wait runs

A child's turn end reaches the parent as news only when a wait is running as it
happens. When the turn ends first, later waits time out and list the child with
its current status instead:

```console
$ hc run --bg --no-notify --label role=agent --name storedone2 -- claude "Reply 'ok' and stop."
$ hc get storedone2 | jq -r .status.state    # once it has replied
done
$ hc wait --children any --timeout 4
{"reason":"timeout","children":[{"terminal":"t7v","reason":"status","status":"done",...}],...}
```

Three such waits returned the same timeout. A child's exit, by contrast, stays
news until one wait takes it, and with no live child left a wait returns at once
with an empty list:

```console
$ hc run --bg --no-notify --name newsprobe -- bash -c 'exit 5'; sleep 1
$ hc wait --children any --timeout 5
{"reason":"children","children":[{"terminal":"t7r","reason":"exit","status":null,"exit_code":5}]}
$ hc wait --children any --timeout 5
{"reason":"children","children":[]}
```

`hc kill` of a done child gave no news either: the next wait returned an empty
list. `hc-child-watch` therefore reads each child's state with `hc get` and uses
`hc wait` only to wake early.

## A Claude Code parent with an active Monitor reports `working`

A Claude Code parent that armed a Monitor and ended its turn showed
`1 monitor still running` on screen, while `hc get` reported its status as
`working` the whole time it waited for input. The Herdr sidebar, and the
parent's own parent, see it as busy while `hc-child-watch` runs.

## A child's `HC_TERMINAL_ID` is its own address

A terminal started with `hc run` gets its own `HC_TERMINAL_ID`, not its
parent's, so an agent told to report to `$HC_TERMINAL_ID` would message itself:

```console
$ echo "parent=$HC_TERMINAL_ID"
parent=t4b
$ hc run --no-notify --name probe -- bash -c 'echo "child=$HC_TERMINAL_ID"'
child=t6n
```

A task passed as a program argument also arrives without the `<hc from=…>` tag
that names the sender.

## opencode reads a bare argument as a directory

`opencode --help` lists `opencode <subcommand> [flags] [<directory>]` and
`--prompt string`, so `opencode "<task>"` would try to open a directory named
after the task. The rule starts an opencode agent with
`opencode --prompt "<task>"`.

## pi's subagents keep the parent's `hc` address

pi's `subagent` tool starts children with the parent's environment minus
`HERDR_*` and pi's own session variables, plus `PI_SUBAGENT=1`
(`modules/home/agents/pi/extensions/subagent/tasks.ts`, `childEnvironment`).
`HC_TERMINAL_ID` therefore names the parent's terminal inside such a child, and
the rule treats `PI_SUBAGENT=1` as the sign that the agent was started by
another one.
