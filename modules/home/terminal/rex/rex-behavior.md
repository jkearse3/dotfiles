# Known Rex behavior

`rex-child-watch` (`child-watch.sh`) and the agent rules' Rex steps rely on the
Rex behavior below, observed with `rex 0.1.0-preview.21`. Some of it differs
from `rex --help`. Rex updates itself outside Nix, so after an update rerun the
reproductions and drop or correct each entry that no longer holds, along with
whatever relies on it. The last section lists the gaps the watcher and rules
leave open because of that behavior.

The examples run in a Rex pane; `$b` is the block ID the previous command
printed.

## `rex window new` names the tab and returns the full block ID

```console
$ rex window new -s "$REX_SESSION" demo -c "$PWD" --keep-open --focus=false --json -- sleep 30
{"window_id":"window:01a213bd-…","block_ids":["block:01a213bd-5a44-…"],…}
$ rex block inspect "$b" --json | jq -c '{session_id, block: .block | {label, window_id}}'
{"session_id":"session:01a1f160-…","block":{"label":"shell","window_id":"window:01a213bd-…"}}
$ rex window ls -s "$REX_SESSION" --json | jq -c '[.windows[].label]'
["Window 1a3b73a8","demo"]
```

The tab is labelled `demo`; the block keeps the label `shell`. `rex run` does
the reverse:

```console
$ rex run -s "$REX_SESSION" --label demo --keep-open --focus=false --json -- sleep 30
{"window_id":"window:01a213e3-…","block_ids":["block:01a213e3-85a3-…"],…}
$ rex block inspect "$b" --json | jq -c '.block.label'
"demo"
$ rex window ls -s "$REX_SESSION" --json | jq -c '[.windows[].label]'
["Window 1a3b73a8","Window 79ceaac2"]
```

`--label demo` labels the block and leaves the tab as `Window <suffix>`.
`$REX_BLOCK` holds the pane's full block ID, such as
`block:01a1f160-47ab-7f32-a7ea-ae7d241953e5`.

```console
$ REX_SESSION=session:00000000-0000-0000-0000-000000000000 rex window ls --json | jq -r '.session_id'
session:01a1f160-…
$ rex window ls -A --json; echo "rc=$?"
Error: rex window ls --json requires one session. Pass -s SESSION
…
rc=2
```

Without `-s`, `rex window ls --json` ignores `$REX_SESSION`: with a session ID
that matches no session, it still lists the only session running. Pass
`-s "$REX_SESSION"` to list your own session's tabs. With `-A` it exits 2.

## Arguments reach the program unchanged

```console
$ rex window new -s "$REX_SESSION" quote --keep-open --focus=false --json -- printf '[%s]\n' 'Say `no earlier context` and $HOME "quoted" it'\''s
line2'
$ rex capture -b "$b" --trim
[Say `no earlier context` and $HOME "quoted" it's
line2]
```

Rex starts the command with the login shell's environment, not through a shell
that would expand it, so an agent's task text arrives byte for byte.

## Panes get the login environment

```console
$ rex window new -s "$REX_SESSION" env --keep-open --focus=false --json -- \
    bash -c 'echo "TMPDIR=$TMPDIR DIRENV=${DIRENV_DIR:-unset}"'
$ rex capture -b "$b" --trim
TMPDIR=/var/folders/39/…/T/ DIRENV=unset
```

An agent's own `$TMPDIR` (for example `/tmp/agent-501/ZdRQI47R/`) and its
project's direnv shell do not carry over.

## Without `--keep-open`, a pane takes its exit code with it

```console
$ rex run -s "$REX_SESSION" --focus=false --json -- bash -c 'sleep 2; exit 4'
$ sleep 4; rex wait "$b" --for 5s --json; echo "rc=$?"
Error: block or window target "block:01a213b6-a868-…" not found
rc=3
$ rex run -s "$REX_SESSION" --focus=false --json -- bash -c 'exit 5'
$ sleep 2; rex wait "$b" --for 5s --json; echo "rc=$?"
{"exit_code":5,"error":"exit status 5"}
rc=5
```

A program that runs past about a second closes its pane when it exits; a faster
failure stays open so its error can be read. `rex wait --help` says a block that
closes before the wait starts returns 1; here it returned 3.

## `rex wait --json` reports through its exit status and stdout

```console
$ rex window new -s "$REX_SESSION" job --keep-open --focus=false --json -- bash -c 'sleep 20; exit 2'
$ rex wait "$b" --for 2s --json; echo "rc=$?"
Error: wait timed out after 2s: context deadline exceeded
rc=1
$ rex wait "$b" --for 30s --json; echo "rc=$?"
{"exit_code":2,"error":"exit status 2"}
Error: exit status 2
rc=2
$ rex window new -s "$REX_SESSION" ok --keep-open --focus=false --json -- true
$ sleep 1; rex wait "$b" --for 5s --json; echo "rc=$?"
{"exit_code":0}
rc=0
```

It exits with the job's code and prints `{"exit_code":N}` to stdout, also when
the job ended before the wait started. A timeout prints nothing to stdout and
exits 1, which a job's own exit 1 also gives, so only the JSON tells them apart.

## Block commands find a full block ID without `-s`; an empty `-b` is your own pane

```console
$ env -u REX_SESSION rex capture -b "$b" --trim
$ env -u REX_SESSION rex wait "$b" --for 2s --json
$ env -u REX_SESSION rex send-key -b "$b" ctrl+c
$ env -u REX_SESSION rex block close "$b"
$ rex block call -b "$b" process; echo "rc=$?"
Error: block target "block:01a213ca-…" not found
rc=3
$ rex block call -b "" process | jq -r .child.name
login
```

`capture`, `wait`, `send-key`, `block call`, and `block close` all accept a full
block ID with no session. `-b ""` falls back to `$REX_BLOCK`, the caller's own
pane (its `login` process above), so an unset shell variable would send keys to
the agent itself.

## Scrollback and closing

`rex capture --help` gives about 64 MiB of scrollback, roughly 100,000 lines,
and `rex capture --trim` prints all of it:

```console
$ rex window new -s "$REX_SESSION" scroll --keep-open --focus=false --json -- seq 1 200000
$ sleep 3; rex capture -b "$b" --trim | wc -l
96400
$ rex capture -b "$b" --trim | head -1
103601
$ rex capture -b "$b" --trim | tail -1
200000
```

`--trim` printed the last 96,400 of the 200,000 lines without a gap, close to
the 100,000-line limit. `rex block close` ends the program still running in the
pane:

```console
$ rex window new -s "$REX_SESSION" demo --keep-open --focus=false --json -- sleep 30
$ rex block close "$b"; rex block call -b "$b" process; echo "rc=$?"
Error: block target "block:…" not found
rc=3
```

## `process` reports how the program ended

```console
$ rex window new -s "$REX_SESSION" sig --keep-open --focus=false --json -- sleep 300
$ kill -9 "$(rex block call -b "$b" process | jq -r .child.pid)"
$ rex block call -b "$b" process | jq -c '{child, last_exit}'
{"child":null,"last_exit":{"exit_code":-1,"error":"signal: killed"}}
$ rex window new -s "$REX_SESSION" int --keep-open --focus=false --json -- sleep 300
$ rex send-key -b "$b" ctrl+c; sleep 1; rex block call -b "$b" process | jq -c .last_exit
{"exit_code":-1,"error":"signal: interrupt"}
```

While the program runs, `child` names it and `last_exit` is null. A normal exit
gives `{"exit_code":N}`, with `error` when N is nonzero.

## Agents' status reports

Claude Code, pi, and opencode report their state with OSC 7501 escape sequences,
which `program_status` returns as `records`, each with `state`, `updated_at`,
and optionally `id`, `kind`, `msg`, and `app`; the root record, with no `id`,
comes first. Each agent below was started with
`rex window new … --keep-open --focus=false --json -- <agent> "<task>"` and its
status read once a second:

```console
$ prev=; for i in $(seq 1 60); do
>   s=$(rex block call -b "$b" program_status | jq -c '[.records[] | {id, state, kind}]')
>   [[ $s != "$prev" ]] && echo "t=$i $s"; prev=$s; sleep 1
> done
```

- Claude Code
  (`claude --name <stem> "Reply with the single word ok, then stop."`): `[]`,
  then `working`, then `done`. Its `done` record kept the same `updated_at` for
  minutes. Run with `--permission-mode default` and a task that runs a shell
  command, it reported `blocked` with `kind` `permission` and the command in
  `msg`. While it runs built-in subagents, each adds a record with an `id` after
  the root record. Its records were empty once it exited.
- pi (`pi --session-id <stem> --name <stem> "<task>"`): `[]`, then `idle`, then
  `working`, then `done`.
- opencode (`opencode --session ses_<stem> --prompt "<task>"`): `[]`, then
  `idle`, then `working` (a root record and one whose `id` is the session), then
  `idle` again at the turn's end, with no `done`. Its final `idle` kept the same
  `updated_at` for over a minute.

Because pi and opencode report `idle` both at startup and, for opencode, at a
turn's end, `rex-child-watch` ignores the first `idle` it records for a child
and reports a later one as a turn's end: after `working` or `blocked`, or when
its `updated_at` is newer than the recorded `idle`'s. A trivial opencode reply
went from `working` to `idle` in about two seconds, the watcher's check
interval, so a turn can end before the watcher sees `working`.

## Known limitations

The watcher and rules accept these gaps rather than work around them.

- **pi and opencode parents poll.** Claude Code's Monitor tool turns each line
  `rex-child-watch` prints into a notification, so a Claude parent ends its turn
  and still reads the user's messages at once. pi and opencode have no such
  tool, so they run `rex-child-watch --until-news` as an ordinary command, at
  most 60 seconds at a time, and see the user's message only when it returns.
  Each rerun costs a model turn.
- **opencode's turn end is inferred.** Claude Code reports `done` at a turn's
  end and pi does too, but opencode reports `idle`, which it also reports at
  startup and, per the Program Status Protocol, when interrupted. The watcher
  therefore ignores the first `idle` it records for a child. A turn that ended
  before the watcher first checked that child is not reported, and an opencode
  `idle` re-sent without a turn, which was not observed, would be reported as
  `done`.
- **A second turn in one child is not reported.** `done` followed by `done`
  reads the same as a re-sent report. Parents never give a child a second turn
  under the rules (they resume it in a new pane instead), so this only arises
  when the user works in the child's tab.
- **One registry per pane.** The watcher keys its state by the parent's block
  ID, so a later agent started in the same pane inherits the earlier one's
  registered children.
- **Sandboxed parents cannot use it.** A parent under a `nono` profile that does
  not grant the Rex socket and `~/.local/state/rex-child-watch` cannot reach Rex
  or keep the watcher's state.
- **Rex is a preview.** These entries hold for `rex 0.1.0-preview.21` and need
  rechecking after each Rex update.

Possible improvements, none built:

- Have a child's result file, rather than its status, signal that a turn ended:
  the parent registers the file's path with the child, and the watcher reports
  `done` when the file appears. That removes the `idle` inference for every
  harness and would suit `hc-child-watch` too.
- Run the watcher as a `rex do` Lua script that handles
  `terminal.program_status_changed` and `terminal.child_exited` events, so no
  change falls between two checks while it runs. The fake-`rex` fixtures could
  no longer test it.
- Give pi a small extension that runs `rex-child-watch` and steers each line
  into the session as a new turn, the way Monitor does for Claude Code, so pi
  parents stop polling.
