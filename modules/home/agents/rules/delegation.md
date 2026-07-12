# Delegation

Delegate only when a subproblem is independently bounded, has a clear deliverable, and benefits
enough from parallelism or isolated context to outweigh coordination cost. Prefer flat delegation.

Give each subagent non-overlapping scope, relevant context, expected output, and verification
criteria. For repository changes, assign exclusive file or subsystem ownership unless concurrent
work is explicitly coordinated.

Do not delegate trivial work, work the parent must immediately redo, or substantially the same work
to multiple agents unless independent comparison is the explicit goal.

Nested delegation is allowed only when the nested task is independently bounded and the parent agent
remains responsible for integrating and validating the result. The originating agent remains
accountable for the final answer and must reconcile conflicts rather than forwarding raw subagent
output.

Require delegated results to state conclusions, decisive evidence, verification performed, and
unresolved risks. Do not forward raw notes as the final result.
