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

Use this managed surface, not raw Herdr, for authorized teammate work. A launch
grants no task, mutation, publication, or cleanup authority. Follow the host's
delegation and approval rules. Never start nested delegation without explicit
human authorization in that conversation. If the managed path fails, stop.

## Normal workflow

Names are immutable within the current endpoint/workspace. Use full `tm_…` IDs
for deliberate cross-workspace access and ambiguous closed names. Request IDs
are global references. JSON schema version 2 is stable; `--json` may appear
before or after the command.

Inspect state and configured profiles:

```sh
pi-shepherd --json profiles
pi-shepherd --json list
pi-shepherd --json show REF
```

Default creation starts a fresh conversation with the calling Pi's provider,
model, and effective thinking level. It requires authoritative Pi shell-tool
context and otherwise fails before mutation. It does not copy messages, tools,
permissions, extension memory, runtime prompt changes, or sandbox policy. An
explicit profile is a static preset and does not inherit caller settings;
inspect it and state the task-specific reason before overriding the default.

```sh
pi-shepherd --json create NAME --cwd "$PWD"
pi-shepherd --json create NAME --profile PROFILE --cwd "$PWD"
```

Record the returned teammate and tab IDs. For parallel work, create all
teammates first and then submit independent requests concurrently. Give each
teammate bounded scope, relevant context, expected result and verification,
explicit write or read-only authority, nonoverlapping ownership, and the rule
against further delegation.

Submit prompts through stdin, preferably from a private producer; do not put
prompt text in arguments, shell strings, or heredocs. Pass `--allow-focused`
only after ensuring the human composer is clear. It bypasses only the focus
check.

```sh
PROMPT_PRODUCER | pi-shepherd --json request REF --stdin --wait --ack --allow-focused
```

`--ack` requires `--wait`. A completed reply is emitted and flushed before its
slot is deleted. Timeout, blocked, unhealthy, uncertain-delivery, and
settled-without-reply outcomes remain pending and report
`ack_outcome=not_completed`. Without `--ack`, completed results remain stored.
There is one request slot, no queue, and no automatic retry or replay.

A teammate normally follows the exact reply instruction appended to its prompt:

```sh
pi-shepherd reply REQUEST_ID --stdin < RESPONSE_FILE
```

Use a private temporary file or direct pipe, never a response argument or shell
string. Limit replies to 256 KiB of UTF-8 and remove only your own temporary
file after confirmed submission. Reply checks the teammate environment, exact
request ID, current managed binding, alias, kind, workspace, tab, and pane.

Recover or acknowledge independently of the original caller:

```sh
pi-shepherd --json result REQUEST_ID --wait --timeout 600
pi-shepherd result REQUEST_ID --ack
pi-shepherd --json cancel REQUEST_ID
```

`result` and `cancel` do not require live Herdr. Pending `result --ack` fails;
completed acknowledgement occurs only after successful output. Cancel removes
only a pending slot and does not stop the agent. Replies are
`cooperative_unverified`: correlation is not authentication or proof that the
task succeeded.

## Unresolved work

Durable `request_status` is only `pending` or `completed`. Treat `wait_outcome`,
`runtime_status`, and `runtime_health` as separate diagnostics. Idle and done
are settled observations, not semantic results. Never replay prepared,
uncertain, timed-out, blocked, unhealthy, or reply-missing work automatically; a
late exact-ID reply may still arrive.

```sh
pi-shepherd --json wait REF --timeout 60
pi-shepherd --json show REF
pi-shepherd read REF --source recent-unwrapped --lines 120
```

Terminal reads are unverified recovery, never a result fallback. They can expose
prompts, secrets, tool traces, incomplete scrollback, and human turns. Ask the
human before answering any approval or question, and do not reinterpret a direct
human turn as a coordinator result.

## Repair and cleanup

```sh
pi-shepherd --json repair REF
pi-shepherd --json repair REF --apply
pi-shepherd --json focus REF
pi-shepherd attach REF
pi-shepherd --json close REF
pi-shepherd --json forget REF
```

Inspection automatically accepts only exact provisioning binding, unique
alias/kind promotion, within-tab pane movement, and positively proven closure.
`repair --apply` refreshes evidence before exact relocation, marker restoration,
or interrupted-close resumption and returns fresh post-repair state. Relocation
requires a full teammate ID.

There is no in-place restart. Missing or uncertain agents require explicit
close/create; never infer from alias absence that a delayed start cannot occur.
Ambiguous identities, changed conflicting markers, foreign occupants, extra
panes, and unaccepted relocation fail closed. Never rank candidates by cwd or
kind. Local locks do not prevent human or raw-Herdr races.

Treat session-created tabs as temporary unless the human asks to retain them.
Before closing, freshly confirm exact task ownership and identity with `show`.
Normal close requires an uncontaminated exact tab, settled runtime, no pending
request, and more than one workspace tab. A missing agent also requires positive
foreground-shell evidence. `close --force` bypasses only pending-work and
runtime-status checks, never identity, contamination, relocation, shell proof,
or final-tab protection. Completed results survive closure.

Normal forget requires closed intent and an empty inbox. `forget --force` may
orphan a tab or discard a result, requires explicit destructive-action
authorization, and never closes a resource. Never close or forget a resource
whose exact identity and task ownership are unknown. Before completion, close
each task-owned temporary tab or report its exact ID and retention reason.

## Privacy

The private database stores plaintext replies, not prompts, terminal captures,
Pi sessions, launch arguments, unrestricted environment, or observation history.
Acknowledgement and cancellation are logical deletion, not secure erasure from
WAL files, backups, or snapshots. pi-shepherd never adopts, migrates, or removes
another tool's state or resources.
