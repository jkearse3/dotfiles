# herdr-core

`herdr-core` (CLI `hc`) runs the persistent terminals behind the Herdr app. This
package wraps the llm-agents build so a core never inherits the Herdr TUI's pane
variables; see `package.nix`.

## Known `hc` behavior

The agent rule `modules/home/terminal/herdr-app/agent-rule.md` works around the
behavior below, observed with `hc 0.1.21`. Some of it contradicts the upstream
`hc --skill` guide. After an update, rerun the reproductions and drop the rule's
matching instruction for anything that no longer holds.

### `--bg --rm` loses a fast job's exit code

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

### A foreground run notifies its caller unless told not to

Without `--no-notify`, a finished `hc run` types a note such as
`t3x exp-fg6 exited (exit 6). Read: hc read t3x` into its parent terminal's
input, which reaches an agent as a new message, even when the run was in the
foreground and already reported the exit code.

### `hc wait` exits 0 whatever the job returned

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

### `hc wait --output` misses earlier output and does not mean the job ended

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

### A terminal keeps about 1,100 lines

`hc read <t> --lines 300000` after `seq 1 200000` returns about 1,120 lines and
warns `[hc] incomplete: older output may be missing`. Lines 200 characters wide
give the same count, so the limit is in lines.

### Jobs get the login environment, not the caller's

A terminal started with `hc run` gets the login session's environment. Inside
it, `$TMPDIR` is the login session's (`/var/folders/.../T/`) rather than the
agent's private one, and a project's direnv shell is not loaded, so tools such
as `pnpm` from a flake devshell are missing. `--cwd` is honoured, and
`direnv exec .` inside the job loads the devshell.

### Removing a terminal leaves its children

`hc rm` on a parent terminal removes only that terminal; its finished children
stay listed in `hc ls --all` until each is removed.
