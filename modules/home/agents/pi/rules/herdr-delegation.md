# Herdr Delegation

Treat the standing delegation authorization as including Herdr for a Pi session
that was not itself delegated by another Pi session. Apply the shared delegation
rules to decide when to delegate, and follow the installed Herdr skill for the
current CLI contract and safety rules. Use Herdr rather than an `Agent` tool or
an in-process subagent extension.

Call the initiating Pi the coordinator and a Pi it starts a teammate; these are
policy roles, not Herdr metadata. A teammate must not create or prompt another
agent unless the human explicitly authorizes that in the teammate's
conversation. This restriction overrides the shared permission to split
delegated work further.

Create each new teammate as a fresh Pi conversation in its own tab, using
`herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" --no-focus`.
This topology overrides the Herdr skill's default sibling pane. Parse the root
pane ID from the response, start a uniquely named `--kind pi` agent there, and
pass Pi arguments after `--`. Keep at most four live teammates created by the
coordinator unless the user requests more. Reuse an existing teammate only when
its conversation is relevant to the follow-up.

Choose each teammate's tools and authority according to its task and owning
skill. Prefer the least capability that can complete the assignment; tool
allowlists reduce model-callable capabilities but are not a sandbox. Keep source
writes in the coordinator by default, and delegate mutation only through an
explicit, non-overlapping assignment.

Apply the shared prompt requirements and always tell each teammate not to
delegate further. For parallel work, start all teammates first, then launch
their `herdr agent prompt <target> <prompt> --wait --timeout <ms>` calls
concurrently. Do not use a later bare `agent wait` as the sole completion check,
because it can match the pre-prompt `idle` state.

Treat `idle` and `done` as settled states, not proof that the task succeeded.
After either state, inspect the response with
`herdr agent read <target> --source recent-unwrapped --lines <n>`. Treat
`blocked`, `unknown`, and timeouts as unresolved: inspect the agent and terminal
rather than assuming completion, and ask the human before answering a blocked
prompt.

If increasing `--lines` cannot recover the response, ask a teammate without
write authority to repeat it in bounded chunks and read each chunk promptly.
After that failed read, a teammate with write authority may instead save the
complete response to a temporary Markdown file and return only its path.

Human turns entered directly in a teammate tab stay in that conversation. Do not
present them as coordinator-requested results unless the human asks the teammate
to report them. Never terminate an agent or close a tab, pane, workspace, or
session that the coordinator did not create unless the user explicitly requests
it.
