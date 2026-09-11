# Herdr Delegation

For a Pi session that was not itself delegated by another Pi session, standing
delegation authorization includes managed Herdr teammates. When the shared
policy calls for delegation, load and follow the installed `pi-shepherd` skill.
Use `pi-shepherd`, not an `Agent` tool or an in-process subagent extension. If
the managed path is unavailable or fails, stop rather than falling back to raw
Herdr.

A managed teammate must not create or prompt another agent unless the human
explicitly authorizes that in the teammate's own conversation. Keep at most four
live teammates created by the initiating session unless the user requests more.
A skill or profile grants no additional task, mutation, publication,
destructive, or sandbox authority.

Keep source writes in the initiating session by default. Delegate mutation only
through an explicit, nonoverlapping assignment. Give each teammate its scope,
necessary context, expected result, verification, and authority. Create all
parallel teammates first, then submit their assignments concurrently. Preserve
cwd and use the managed no-focus tab topology. Choose a concise, task-derived
logical name; the CLI includes it in the tab label alongside the stable identity
marker. Record the returned teammate and tab IDs. Default creation twins the
calling Pi provider, model, and thinking level; use `--profile` only for an
explicit task-specific override.

Names resolve only in the caller's workspace; full teammate IDs deliberately
cross workspace boundaries. Workspace affinity is same-user accident prevention,
not authentication or task authority. The caller's ability to manage a teammate
does not authorize changing unrelated work or closing another session's
resources.

Use `request --wait --allow-focused` and retain its exact request ID. There is
one request/result slot per teammate, with no queue or automatic replay. A
teammate must submit its final response with `reply REQUEST_ID --stdin` or
`--file`, not response text in command arguments. Use private file-writing tools
or a producer's stdout rather than embedding the body in shell command strings.
The result is `cooperative_unverified`, not proof of semantic success. Inspect
the result and explicitly acknowledge it with `result REQUEST_ID --ack` when no
longer needed.

A blocked, missing-reply, timeout, or uncertain delivery remains unresolved and
retains its slot. Use `show`, `result`, and explicit unverified `read`
inspection; never derive a semantic result from a terminal or native session.
`cancel` removes only pending work and does not interrupt the teammate. Ask the
human before answering an approval or question. If human terminal input is known
or suspected, wait for confirmation that the composer is clear before prompting
again.

Use `repair` to inspect a proposal and `repair --apply` only for a named,
proof-backed action within the host's authority. Missing agents require explicit
close/create; repair never restarts them or alters their inbox. Fresh creation
uses a new ID and conversation, while old completed results remain retrievable.
Never choose among ambiguous resources, replay an unconfirmed launch, or
silently accept relocation. Full teammate IDs are required for relocation
repair. Human turns entered directly in a teammate tab remain part of that
conversation, not requested coordinator output.

Treat every teammate tab created by the initiating session as temporary unless
the user explicitly asks to retain it. After collecting its response, close the
teammate with `pi-shepherd close TEAMMATE_ID` unless its work is unresolved, it
is blocked awaiting human input, or the human has interacted with or asked to
retain it. Before completing the task, verify that every session-created
teammate tab is closed or retained under one of those exceptions; report each
retained tab ID and the reason it remains open.

Before cleanup, freshly confirm task ownership and exact identity using `show`.
Never terminate an agent or close a pane, tab, workspace, or session without
that confirmation unless the human explicitly authorizes bypassing those
safeguards. Normal close requires settled work and no pending request; completed
results remain retrievable. Force never bypasses exact identity, contamination,
unaccepted relocation, or final-workspace-tab protection. Forced forget can
orphan resources or discard results and requires explicit destructive-action
authorization. If safe cleanup cannot be confirmed, retain the tab as unresolved
and report why rather than bypassing a protection.

Managed coordination never falls back to raw Herdr. This does not restrict
separately authorized raw terminal control: load and follow the separate `herdr`
skill for that work. During managed recovery, raw Herdr remains limited to
bounded diagnostic cases permitted by the `pi-shepherd` skill and host policy.
