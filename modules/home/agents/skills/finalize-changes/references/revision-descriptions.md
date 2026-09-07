# Revision Descriptions

Repository documentation determines the revision description format. When the
repository does not specify one, use Conventional Commits:
`type(scope): description`, with an optional scope and `!` for breaking changes.

Default types are `feat`, `fix`, `refactor`, `perf`, `style`, `chore`, `docs`,
`test`, `ci`, and `build`. Use an imperative lowercase description without a
period, and keep the complete subject under 72 characters. Choose the type by
effect: agent configuration is `feat` when behavior changes, `refactor` when
reorganized, and `docs` only when behavior is unchanged.

Every agent-authored description requires a non-redundant body. Use the body to
record useful context or details that are not obvious from the subject.

Explain why when a meaningful rationale is known. Include prior state or
constraints only when they add value. If no useful rationale is apparent,
emphasize non-obvious implementation details, durable behavior, compatibility,
risks, exclusions, or a design choice whose consequence the diff does not
already reveal.

When a description explains a change by its prior behavior, a constraint, or a
precedent, state that directly so the description is resolvable from itself and
its own diff; cite an issue, commit, or component by name only to reinforce what
the description already explains, never as the pointer a reader must follow to
recover it.

Give each distinct chunk of information its own paragraph. In particular, keep
prior state or constraints, the change made in response, and auxiliary details
in separate paragraphs when more than one appears.

Exclude review history, tool output, scratch work, agent actions, task state,
workflow narration, alternatives weighed but not taken, and unsupported claims.
Never reference internal planning structure — plan or phase names, stage or step
numbers, or milestone labels such as "Stage 1" or "Step 3"; describe the change
in durable terms instead.

Wrap body and footer lines at 72 characters except unbreakable URLs and inline
code. Separate footers from the body with a blank line, keeping each footer on
its own line.

When the change set has a governing issue or ticket, record it as a footer
trailer: a closing keyword (`Closes`, `Fixes`, `Resolves`) when the change
resolves it, `Refs` when it only relates, in the tracker's own reference syntax
(`Closes #123` for GitHub, `Fixes PROJ-123` for Jira or Linear). Source the
identifier from the task-owned branch or bookmark name, the plan or contract in
scope, or the issue description driving the work, and omit the trailer only when
no such issue exists. The trailer is a cross-reference and automation aid, not a
substitute for a self-resolvable description. Use `BREAKING CHANGE:` as
applicable.

Format each complete agent-authored message into `desc`, validate that exact
value, and pass it unchanged to the mutation:

```bash
desc="$(printf '%s\n' "$desc" | commit-message format)"
printf '%s\n' "$desc" | commit-message validate
```

If validation fails, revise and repeat. Never format an exact user-supplied
message; if it fails validation, stop and report the failure.
