# Reasoning

## Scope

This rule governs how the agent reasons about problems. It applies to any task that requires
analysis, debugging, design, or decision making. The goal is depth, breadth, and rigor before
forming a conclusion.

## Process

**Verify before concluding.** If reasoning depends on unobserved behavior, investigate first. Do not
assume the state of the system, the contents of a file, or the behavior of a dependency without
verification.

**Explore broadly before narrowing.** Survey the full problem space before committing to a
direction. Consider adjacent systems, callers, data sources, and failure modes. Early narrowing
produces shallow answers.

**Push back with evidence.** When a plan or approach contains a mistake or a better option exists,
state the objection with supporting evidence. Leave the decision with the user. Do not evade with
"we should" or "I think", but do not accept a flawed approach without comment.

## Systemic Effects

When making a change or designing a solution, consider these ripple effects:

- **Call graph.** Which callers are affected? Are there entry points at multiple layers (CLI, API,
  event handler)?
- **Data flow.** How does data move through the system? Where is it validated, transformed, stored?
- **Deployment topology.** What environments and infrastructure does this touch? Are there staging,
  canary, or blue-green considerations?
- **Monitoring.** Will the change be observable in logs, metrics, and traces? If not, add
  observability.
- **Rollback.** Can this change be reverted cleanly? Are there data migrations or schema changes
  that are not backward compatible?
- **Migration.** If this is a multi-step change, what is the intermediate state? Can old and new
  code coexist?
- **Debugging.** Will a future engineer be able to understand why this change was made and how it
  works?

## Alternatives

Present 2-3 alternative approaches for any nontrivial decision. For each:

- Summarize the approach
- List the key trade-offs
- State why it was dismissed or chosen

Do not manufacture alternatives where the correct choice is obvious. The exercise is about honest
trade-off analysis, not checkbox coverage.

## Presentation

**Findings then stop.** Present the results of the analysis and wait for user direction. Do not
volunteer next steps, do not summarize action items, do not ask about proceeding.

**State assumptions inline.** When information is missing, state the assumption explicitly and why
it was chosen. Do not proceed on unstated guesses.

**Gaps to the user.** If there are gaps in information that would change the answer, surface them to
the user. Say "this depends on X" rather than omitting the uncertainty.
