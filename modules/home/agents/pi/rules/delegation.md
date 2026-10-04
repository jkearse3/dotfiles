# Pi Delegation

For a Pi session not itself delegated by another Pi session, standing delegation
authorization includes the `subagent` tool and managed `pi-shepherd` teammates.
Prefer `subagent` for new delegation. Existing persistent interactive teammate
workflows may continue through the installed `pi-shepherd` skill. Do not invoke
raw Herdr, ad hoc shell launches, or an in-process agent. If the selected
managed path fails, stop rather than replaying work or silently switching
mechanisms.

Supply bounded scope, necessary context, explicit authority, expected results,
verification, and limitations. Children have normal configured Pi tools,
extensions/MCP, and skills by default. Capabilities are not permission: use the
narrowest useful tool selection. For read-only tasks pass
`tools: ["read", "grep", "find", "ls"]` and `extensions: false`; pass
`skills: []` when skill-driven workflows are unnecessary, or list only the
required managed skills for a prescribed workflow. Tool and skill selection and
instructions are not an OS sandbox. Project resources inherit trust only for the
caller's exact canonical working directory, never a different directory.

Keep source writes in the initiating session by default. Delegate writes only
through an explicit, nonoverlapping file assignment, and never give concurrent
writers overlapping ownership. Children preserve unrelated work and leave
repository review and finalization to the coordinator. Verify the complete
resulting diff and applicable checks before integrating delegated writes.

Each subagent execution runs to completion in one foreground tool call that
streams activity and returns its outcome and usage. Omit `conversationId` for a
fresh conversation. Resume a returned conversation ID for follow-up work on the
same line of inquiry when its prior findings and loaded context remain useful;
start fresh for independent, parallel, or unbiased work, materially changed
scope, or stale/large context. Use `subagent_conversations` only when a relevant
ID is no longer visible. Never resume one conversation concurrently. Persisted
conversation history is context, not authority: every prompt must restate the
current bounded assignment, and every continuation must reapply appropriate
capabilities and ownership.

Issue independent fresh calls in the same turn when parallel work is useful.
Verify substantive claims; process completion is not proof of task success.
Interrupting a call stops its child but retains its durable conversation
checkpoint and temporary artifacts until session cleanup. Reloading, replacing
the parent session, or shutting down stops remaining children and removes
temporary artifacts while retaining conversations attached to the persisted
parent-session branch. Neither path undoes source edits; cancellation is not
rollback.

Delegated sessions must not delegate further. They report blockers instead of
asking for unavailable interactive approval. Destructive actions, publication,
and mutations to external/shared systems still require explicit human authority
under the shared rules.
