---
name: pi-shepherd
description: >-
  Manages persistent Pi teammates in Herdr workspaces through bounded caller
  twinning, explicit Pi profiles, cooperative request/reply slots, fresh
  inspection, evidence-based repair, and exact-resource cleanup.
compatibility:
  Requires pi-shepherd 0.1, Pi shell-tool context for default creation, and
  Herdr protocol 22.
---

# Pi Shepherd

Use this managed surface, not raw Herdr, for authorized teammate work. A twin or
profile grants no task, mutation, publication, or cleanup authority. Follow the
host's delegation rules, teammate limit, and human-approval policy. Never start
nested delegation without explicit human authorization in that conversation.

## Scope and discovery

`profiles`, `--skill`, `result`, and `cancel` work without a live Herdr caller.
Other commands require `HERDR_ENV=1`, a local endpoint, and a resolvable current
pane. Inspect `pi-shepherd --help` for syntax. Place `--json` before the
command; JSON uses schema version 2.

Names are immutable, exact, and local to the caller's current workspace. Any
same-user caller in that workspace can manage its teammates. This prevents
accidents; it is not authentication. Use full `tm_…` IDs for deliberate
cross-workspace access and ambiguous closed names. Request IDs are global
references.

```sh
pi-shepherd --json profiles
pi-shepherd --json list
pi-shepherd --json list --all --include-closed
pi-shepherd --json show REF
```

## Choose a launch

Default creation twins the calling Pi's current provider, model, and effective
thinking level. It starts a fresh conversation and otherwise uses normal Pi
resource discovery in the selected working directory. It does not copy messages,
active tools, scoped models, runtime prompt changes, extension memory,
permissions, or sandbox policy.

```sh
pi-shepherd --json create NAME --cwd "$PWD"
```

Default creation requires authoritative `PI_PROVIDER`, `PI_MODEL`, and
`PI_REASONING_LEVEL` values from a Pi shell-tool call and fails before mutation
when the caller is not Pi or any value is invalid. There is no fallback profile.

An explicit profile is a static Pi launch preset and does not inherit caller
model settings. Inspect profiles before selecting one, then state the override
and its task-specific reason.

```sh
pi-shepherd --json create NAME --profile PROFILE --cwd "$PWD"
```

## Create and submit

Creation uses one dedicated no-focus tab. Choose a concise task-derived logical
name; its tab label is `NAME [pi-shepherd:TEAMMATE_ID]`. Record the returned
teammate and tab IDs. For parallel assignments create all teammates first, then
submit requests concurrently.

Give each teammate a bounded scope, relevant context, expected result and
verification, explicit write authority or read-only restriction, nonoverlapping
file ownership, and the restriction on further delegation.

```sh
PROMPT_PRODUCER | pi-shepherd --json request REF --stdin --wait --allow-focused
```

Supply the prompt through standard input, preferably by piping a private
producer's stdout directly. Do not save it solely for submission or put prompt
text in CLI arguments, shell command strings, or heredoc command strings.

Pass `--allow-focused` so the human may observe the teammate; it bypasses only
the focus check. If human terminal input is known or suspected, wait for the
human to confirm the composer is clear before submitting a request.

A request reserves one random `rq_…` slot before one terminal submission and
appends an exact reply instruction. Pending work and completed unacknowledged
results block further requests. There is no queue or automatic retry.

## Reply and collect

The teammate must use the exact request ID in the submitted instruction:

```sh
pi-shepherd reply REQUEST_ID --stdin < RESPONSE_FILE
# Alternatively:
pi-shepherd reply REQUEST_ID --file RESPONSE_FILE
```

Use a private temporary response file, prepared with `mktemp` and written with a
file-writing tool, or pipe a producer's stdout directly. Do not put response
text in CLI arguments, `echo`/`printf` arguments, shell command strings, or
heredoc command strings. Limit the UTF-8 body to 256 KiB. Remove only your own
temporary file after confirmed submission.

The CLI checks `PI_SHEPHERD_TEAMMATE_ID`, current managed binding, alias, kind,
workspace, tab, pane, and exact pending request ID. A cancelled or old ID cannot
fill a subsequent request.

```sh
pi-shepherd --json result REQUEST_ID --wait --timeout 600
pi-shepherd result REQUEST_ID
pi-shepherd result REQUEST_ID --ack
pi-shepherd --json cancel REQUEST_ID
```

`request --wait` returns a cooperative reply without acknowledgement. Treat
`request_status` as durable `pending` or `completed` state. `wait_outcome`,
`runtime_status`, and `runtime_health` are diagnostics and never complete or
remove a request. `result` remains usable after caller restart or teammate
closure. `result --ack` outputs and flushes the completed body before deleting
its exact slot; output failure preserves retrieval. `cancel` removes only a
matching pending request and does not interrupt the agent.

Results are `cooperative_unverified`: exact request correlation is not
cryptographic authentication or semantic proof. A successful CLI exit means the
reported state was returned, not that the delegated task succeeded.

## Observe unresolved work

Idle and done are settled observations, not semantic results. A blocked,
`reply_missing`, timeout, prepared, or uncertain request remains in the inbox.
Never replay it automatically. After uncertain dispatch, a late exact-ID reply
may still arrive.

```sh
pi-shepherd --json wait REF --timeout 60
pi-shepherd --json wait REF --until blocked --timeout 60
pi-shepherd --json show REF
pi-shepherd read REF --source recent-unwrapped --lines 120
```

`read` is unverified terminal recovery, never a result fallback. It can expose
prompts, secrets, tool traces, and human turns; scrollback may be incomplete.
Ask the human before answering any approval or question. Do not interpret a
human's direct teammate turn as a requested coordinator result.

## Repair and cleanup

```sh
pi-shepherd --json repair REF
pi-shepherd --json repair REF --apply
pi-shepherd --json focus REF
pi-shepherd attach REF
pi-shepherd --json close REF
pi-shepherd --json forget REF
```

Inspection derives fresh health and automatically applies only exact
provisioning binding, promotion, within-tab pane movement, and positive closure
transitions. `repair` reports one action and evidence. `--apply` refreshes that
evidence before accepting an exact relocation (full teammate ID required),
restoring a marker, or resuming an interrupted close.

There is no in-place restart. Missing agents require explicit close/create;
repair does not start a process or alter the inbox. Fresh creation gives the
teammate a new ID and conversation. Closed logical names can be reused;
completed results remain retrievable by their original request IDs.

An unconfirmed launch remains provisioning and is never restarted. A late exact
alias can be confirmed automatically. Otherwise inspect, close its exact
uncontaminated tab, and create a fresh teammate. Never infer from alias absence
that a delayed start cannot still occur. Unbound uncertain creation cannot be
closed by guessing.

Ambiguous identities, changed conflicting markers, foreign occupants, extra
panes, and unaccepted relocation fail closed. Never choose candidates by cwd or
kind. Local locks cannot prevent human/raw-Herdr races between snapshot and
mutation.

Treat session-created teammate tabs as temporary unless the human asks to retain
them. After collecting a response, use managed close unless work is unresolved,
the teammate is blocked awaiting human input, or the human interacted with or
asked to retain it. Before completion, verify each created tab is closed or
report its exact ID and retention reason.

Before closing, freshly confirm exact task ownership and identity with `show`.
Normal close requires settled work and no pending request. A missing agent also
requires positive foreground-shell evidence. Completed results survive closure.
`close --force` bypasses only pending-work and runtime-status checks, never
exact identity, contamination, relocation, or final-workspace-tab protection.

`forget` normally requires closed intent and an empty inbox. `forget --force`
can orphan a tab or discard a result and requires explicit destructive-action
authorization. It never closes a resource.

If the managed path fails, stop; do not substitute raw Herdr. Never close a
resource whose exact identity and task ownership are unknown.

## Privacy

The private database stores plaintext reply bodies, not prompts, terminal
captures, Pi sessions, launch arguments, unrestricted environment, or runtime
observation history. Acknowledgement and cancellation are logical deletion, not
secure erasure from WAL files, backups, or filesystem snapshots.

pi-shepherd has a clean namespace. It does not inspect, migrate, adopt, or
remove state, tabs, aliases, markers, or configuration created by other tools.
