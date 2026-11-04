# Revision Descriptions

Repository documentation determines the revision description format. When the
repository does not specify one, use Conventional Commits:
`type(scope): description`, with an optional scope and `!` for breaking changes.

Default types are `feat`, `fix`, `refactor`, `perf`, `style`, `chore`, `docs`,
`test`, `ci`, and `build`. Use an imperative lowercase description without a
period. Aim for a complete subject of about 50 characters; 72 characters is the
hard limit the validator enforces. Choose the type by effect: agent
configuration is `feat` when behavior changes, `refactor` when reorganized, and
`docs` only when behavior is unchanged.

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
code. The final metadata section is the footer block: separate it from the body
with a blank line, keep its entries contiguous, and put each entry on its own
line. A native Git trailer uses `Token: value`, with one space after the colon
and hyphens instead of spaces in its token. Use established hyphenated tokens
such as `Signed-off-by` and `Co-authored-by`; the supported conventional
single-word tokens are `Cc`, `Link`, and `Reverts`. This bounded vocabulary
keeps ordinary prose such as `Records: ...` unambiguous. Wrapped trailer values
use indented continuation lines. `BREAKING CHANGE: description` is the
Conventional Commits exception to the token rule and may continue flush left.

Issue-reference footers in agent-authored descriptions always use `Refs`, never
`Closes`, `Fixes`, or `Resolves`, on every revision, including the last revision
of a stack and a single-revision change set: a revision only contributes to an
issue, and the pull request that merges the change set resolves it. `Refs` is a
tracker command, not a `Token: value` trailer: follow the keyword with one space
and no colon, then exactly one tracker identifier: `#123` or
`owner/repository#123` for GitHub, and `PROJ-123` for Jira or Linear. Put
multiple issues on separate footer lines, and never append punctuation to an
issue identifier. Generic trailer values are free-form prose; when the value is
an opaque URL, hash, or identity, preserve that value exactly rather than
punctuating it as a sentence.

When the change set has a governing issue or ticket, source its identifier from
the task-owned branch or bookmark name, the plan or contract in scope, or the
issue description driving the work. Omit the issue-reference footer only when no
such issue exists. It is a cross-reference and automation aid, not a substitute
for a self-resolvable description. Do not invent an issue reference, sign-off,
reviewer, or external link.

Format each complete agent-authored message into `desc`, validate that exact
value, and pass it unchanged to the mutation:

```bash
desc="$(printf '%s\n' "$desc" | commit-message format)"
printf '%s\n' "$desc" | commit-message validate --require-body --conventional
```

`--require-body` applies to every agent-authored description and enforces the
body rule above. `--conventional` checks the Conventional Commits subject with
the default types; pass it whenever repository documentation does not define its
own description format, and drop only `--conventional` when it does.

When a governing issue requires `issue_footer`, such as `Refs PROJ-123`,
validate its exact presence with
`commit-message validate --require-body --conventional --require-footer "$issue_footer"`,
dropping `--conventional` by the same rule. Repeat `--require-footer` for each
required issue-reference footer.

If validation fails, revise and repeat. Never format an exact user-supplied
message; validate it unchanged with plain `commit-message validate`, adding only
any required `--require-footer` options, and if it fails validation, stop and
report the failure.
