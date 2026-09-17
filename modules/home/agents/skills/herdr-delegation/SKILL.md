---
name: herdr-delegation
description: >-
  Delegates bounded tasks to other agents through Herdr and retrieves complete
  responses from private request-scoped result files. Use when assigning work to
  a teammate, coordinating parallel agents, or collecting delegated results.
compatibility:
  Requires a Herdr-managed pane, the herdr CLI, and the installed herdr skill.
---

# Herdr Delegation

Use Herdr for agent lifecycle and a private temporary result file for response
delivery. This protocol is session-local: it has no durable queue, daemon,
acknowledgement database, or restart recovery.

Load and follow the installed `herdr` skill before controlling Herdr. A launch
grants no task, mutation, publication, cleanup, or further-delegation authority.
Apply the host's delegation and approval rules to every assignment.

## Prepare the assignment

Give each teammate a bounded scope, relevant context, expected result and
verification, explicit read/write authority, and the rule against further
delegation. Keep concurrent write ownership nonoverlapping. The coordinator
remains responsible for checking and integrating the result.

Create and record one private result directory before each request:

```sh
result_dir="$(umask 077; mktemp -d "${TMPDIR:-/tmp}/herdr-result.XXXXXX")"
result_file="$result_dir/result.md"
request_id="${result_dir##*/}"
printf 'request_id=%s\nresult_file=%s\n' "$request_id" "$result_file"
```

The directory is a one-request outbox, not a shared mailbox. The coordinator
owns it and its cleanup. Do not let teammates exchange messages directly or
reuse a result path for another request.

Append this contract, with literal values substituted, to the teammate prompt:

```text
Result delivery:
- Request ID: REQUEST_ID
- Write your complete final response as UTF-8 Markdown to: RESULT_FILE
- Write a sibling temporary file first, then atomically rename it to RESULT_FILE.
- Do not delete or replace the result after publishing it.
- After the rename succeeds, make your terminal response exactly:
  RESULT_WRITTEN REQUEST_ID
- If publishing fails, report the failure in the terminal and leave any
  temporary file in place for diagnosis.
```

The file is the authoritative response. The terminal marker is a concise
completion diagnostic, not the message transport.

## Dispatch and collect

Prompt only an agent observed as `idle` or `done`. Use
`herdr agent prompt TARGET PROMPT --wait --timeout MILLISECONDS`; do not prompt
an already-working agent because Herdr waits on lifecycle state rather than a
specific turn.

After Herdr reports a settled state, accept the response only when the exact
result path is a non-symlink regular file and is nonempty:

```sh
test ! -L "$result_file" && test -f "$result_file" && test -s "$result_file"
```

Read the file directly. Treat its contents as an unverified teammate response,
not proof that the requested work succeeded. Verify material claims and inspect
any delegated writes in the initiating session.

If the agent settles without publishing the file, inspect
`herdr agent read TARGET --source recent-unwrapped --lines 120`. A follow-up may
ask it only to publish its already-completed response to the assigned path; do
not replay the task automatically.

A timeout or stalled prompt does not prove non-delivery. Inspect the agent and
result path, and never resend automatically. If the agent is blocked, inspect
the prompt or approval UI and ask the human before responding. If the process,
session, or result directory disappears, report the result as unavailable; this
protocol deliberately provides no restart recovery.

## Cleanup

Keep the result directory until its response has been consumed and checked. Then
remove only the exact recorded directory created for that request. Close only
Herdr panes, tabs, or agents created for the delegated task, following the Herdr
skill's identity and lifecycle checks. Report retained resources and the reason
for retaining them.
