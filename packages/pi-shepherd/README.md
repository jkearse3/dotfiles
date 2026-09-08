# pi-shepherd 0.1

`pi-shepherd` manages persistent Pi teammates in Herdr workspaces. Herdr owns
the terminal and process lifecycle; pi-shepherd adds stable teammate identities,
a cooperative request/result slot, and fail-closed lifecycle recovery. It does
not read Pi sessions or derive results from terminal output.

The [packaged skill](src/pi_shepherd/SKILL.md) describes normal and recovery
workflows. `pi-shepherd --skill` prints that exact file without configuration,
registry, or server access. [Architecture](ARCHITECTURE.md) maps implementation
and safety boundaries.

## Public interface

```text
pi-shepherd --skill
pi-shepherd [--json] profiles
pi-shepherd [--json] create NAME [--profile PROFILE] [--cwd PATH]
  [--startup-timeout SECONDS]
pi-shepherd [--json] list [--all] [--include-closed]
pi-shepherd [--json] show REF
pi-shepherd [--json] request REF (--stdin | --prompt TEXT | --prompt-file PATH|-)
  [--wait] [--timeout SECONDS] [--allow-focused]
pi-shepherd [--json] reply REQUEST_ID (--stdin | --file PATH)
pi-shepherd [--json] result REQUEST_ID [--wait] [--timeout SECONDS] [--ack]
pi-shepherd [--json] cancel REQUEST_ID
pi-shepherd [--json] wait REF [--until STATUS] [--timeout SECONDS]
pi-shepherd [--json] read REF [--source SOURCE] [--lines N] [--ansi]
pi-shepherd [--json] focus REF
pi-shepherd attach REF
pi-shepherd [--json] repair REF [--apply]
pi-shepherd [--json] close REF [--force]
pi-shepherd [--json] forget REF [--force]
```

`REF` is a full `tm_…` ID or an exact immutable logical name matching
`[a-z][a-z0-9_-]{0,63}` without the reserved `tm_` prefix. Active names are
unique within an endpoint/workspace. Closed names may be reused; an ambiguous
closed name requires its full ID. `list --all` discovers other workspaces on the
same endpoint; full IDs deliberately address them. Workspace affinity prevents
accidents but is not an authorization boundary between same-user processes.

JSON success is `{schema_version:2,ok:true,command,result}`; application failure
is `{schema_version:2,ok:false,command,error:{code,message,uncertain}}`. CLI
syntax errors exit 2, application failures exit 1, and success exits 0. Human
`read` and completed-result output is plain content; other human output is
structured JSON text. `attach` requires TTY streams and rejects JSON mode.

`profiles`, `--skill`, `result`, and `cancel` work without a live Herdr session.
Other commands require the caller's Herdr context and protocol 22/schema 1.

## Pi launch behavior

Default creation makes a fresh twin of the calling Pi's bounded launch
configuration:

```sh
pi-shepherd create reviewer
```

The caller must be a Pi agent. The command copies the current `PI_PROVIDER`,
`PI_MODEL`, and `PI_REASONING_LEVEL` values into `--provider`, `--model`, and
`--thinking`. It uses the caller's `PWD` unless `--cwd` overrides it. Missing,
malformed, unsupported, or non-Pi caller context fails before registry or Herdr
mutation; there is no static fallback.

A twin starts a fresh conversation and performs normal Pi resource discovery in
the selected working directory. It does not copy conversation content, active
tool selection, scoped models, runtime prompt modifications, extension memory,
permissions, or sandbox policy.

Explicit profiles are separate Pi launch presets:

```toml
# ${XDG_CONFIG_HOME:-~/.config}/pi-shepherd/config.toml
startup_timeout_seconds = 30
wait_timeout_seconds = 600
read_source = "recent-unwrapped"
read_lines = 120

[profiles.readonly-reviewer]
args = ["--model", "claude-sonnet-4-8", "--thinking", "high",
        "--tools", "read,grep,find,ls"]
env = { REVIEW_MODE = "readonly" }
selection_hint = "Read-only review with a fixed model"
```

```sh
pi-shepherd create reviewer --profile readonly-reviewer
```

Profiles contain exact Pi arguments, optional string environment entries, and an
optional public selection hint. They are used only when named with `--profile`;
caller model settings are not appended. There are no built-in or default
profiles. Unknown keys and malformed types fail closed. `HERDR_*`,
`PI_SHEPHERD_*`, `XDG_STATE_HOME`, and `XDG_RUNTIME_DIR` environment keys are
reserved for routing and state. Arguments and environment values are neither
returned by `profiles` nor persisted.

## Cooperative exchange

Submit new request bodies through `request --stdin`; `--prompt` and
`--prompt-file` remain available for compatibility. `request` reserves an `rq_…`
ID before dispatch and appends the exact `pi-shepherd reply` command. A pending
or completed-unacknowledged slot prevents another request. The teammate supplies
at most 256 KiB of UTF-8 through stdin or a file. `PI_SHEPHERD_TEAMMATE_ID`,
live alias/kind, accepted binding, and pending request ID must all agree. A
stale request ID cannot fill a later slot.

`request --wait` polls for a cooperative reply without acknowledging it. Durable
`request_status` is only `pending` or `completed`; `wait_outcome`, runtime
status, and health are separate observations. Blocked, unhealthy, timed-out,
uncertain-delivery, and settled-without-reply states preserve the request.
`result --wait` polls durable state and remains usable after agent or server
termination. Replies are labeled `cooperative_unverified`: exact correlation is
not authentication or proof of semantic success. Terminal text is never a result
fallback.

A prepared or uncertain request is never replayed. `cancel` conditionally
deletes only a pending request and does not stop the process. `result --ack`
flushes a completed reply before conditional deletion. Output failure preserves
the result, and reply/cancel races have one database winner.

## Lifecycle and repair

Creation reserves intent, creates one no-focus dedicated tab with a verified
working directory, persists its binding, starts one Pi alias, and confirms it
from a fresh snapshot. New tab labels are `NAME [pi-shepherd:TEAMMATE_ID]`; only
that exact form is accepted. Incomplete external effects retain provisioning
intent and are not replayed.

Automatic transitions are limited to exact provisioning binding, unique
alias/kind promotion, agent-pane refresh within the accepted tab, and positively
proven closure. `repair` reports one action and its evidence. `repair --apply`
rechecks that evidence before accepting an exact relocation, restoring the exact
marker, or resuming an interrupted close. Relocation requires a full teammate
ID. There is no in-place restart or candidate ranking.

Normal close requires an exact uncontaminated tab, more than one tab in its
workspace, settled runtime, and no pending request. When the agent is absent,
positive foreground-shell evidence is required even with force. `--force`
relaxes only runtime and pending-work checks. Completed results remain
retrievable after closure. Normal forget requires closed intent and an empty
inbox; forced forget warns that it can orphan a tab or discard a result.

## Private state

The registry is
`${XDG_STATE_HOME:-~/.local/state}/pi-shepherd/registry.sqlite3`. Locks use
`$XDG_RUNTIME_DIR/pi-shepherd/locks` or a private `pi-shepherd-$UID/locks`
directory under the platform temporary directory. Directories and files are
private and reject unsafe links, ownership, modes, hardlinks, and sidecars.

The registry stores teammate intent and one request/result slot. Reply bodies
are plaintext. Prompts, terminal captures, launch arguments, unrestricted
environment, Pi session data, and runtime observation history are not stored.
Acknowledgement is logical deletion, not secure erasure from SQLite WAL files,
backups, or filesystem snapshots.

This namespace is independent of prior tools. pi-shepherd does not inspect,
migrate, adopt, or remove their configuration, state, tabs, aliases, or markers.

## Development

```sh
PYTHONPATH=packages/pi-shepherd/src python3 -B -m unittest discover \
  -s packages/pi-shepherd/tests -p 'test_*.py'
./x.sh fmt
./x.sh lint
./x.sh nix-eval-all
./x.sh nix-build-home
nix build .#pi-shepherd --no-link
```

Automated tests use fake Herdr and disposable private roots. Live verification
requires separately authorized disposable resources and must not activate Home
Manager.
