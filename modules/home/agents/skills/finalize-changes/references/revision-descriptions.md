# Revision Descriptions

Repository documentation determines the revision description format. When the
repository does not specify one, use Conventional Commits:
`type(scope): description`, with an optional scope and `!` for breaking changes.

Default types are `feat`, `fix`, `refactor`, `perf`, `style`, `chore`, `docs`,
`test`, `ci`, and `build`. Use an imperative lowercase description without a
period, and keep the complete subject under 72 characters. Choose the type by
effect: agent configuration is `feat` when behavior changes, `refactor` when
reorganized, and `docs` only when behavior is unchanged.

Every agent-authored description requires a non-redundant body explaining why.
Describe the prior state or constraint, then the response. Include material
constraints, durable behavior, compatibility, risks, exclusions, and non-obvious
choices. Exclude review history, tool output, scratch work, agent actions, task
state, workflow narration, and unsupported claims.

Wrap body and footer lines at 72 characters except unbreakable URLs and inline
code. Separate footers with a blank line; use `Closes #123`, `Fixes JIRA-456`,
and `BREAKING CHANGE:` as applicable.

Format each complete agent-authored message into `desc`, validate that exact
value, and pass it unchanged to the mutation:

```bash
desc="$(printf '%s\n' "$desc" | commit-message format)"
printf '%s\n' "$desc" | commit-message validate
```

If validation fails, revise and repeat. Never format an exact user-supplied
message; if it fails validation, stop and report the failure.
