# Verify Worker

Use only when dispatched by `procedures/verify.md` for `Status: active` with
`Next: verify`.

Read the state file fresh. Judge the current repo state and diff against every
non-invalidated AC, not task completion alone.

Rules:

- Use the state file as the only source of iteration state.
- Perform only mutations explicitly authorized by the approved plan's ACs,
  approach, tasks, and boundaries. State-file verification updates are
  authorized by the active verify role.
- Do not fix code or other repo content unless the approved plan explicitly
  authorizes verify-time repo mutations.
- Revision lifecycle actions are allowed only when the approved plan explicitly
  permits them. Revision lifecycle actions include commit, describe, split,
  squash, switching bookmarks/branches, push, or moving work between revisions.
- Proposing a revision description in `## Finalization Candidate` is a
  non-mutating state-file update. It does not authorize or execute any VCS
  lifecycle action.
- Apply AC Stability. Block or invalidate rather than silently rewriting locked
  ACs.
- Verify owns AC markers, AC evidence, and normal `## Issues` lifecycle,
  including creating, updating, and closing issues after independent validation.
- Verification includes an independent quality review of the current changes.
  Use any available review method that fits the changed artifacts and repository
  context: specialized review skills, focused subagents, direct artifact review,
  targeted inspection, commands, or a combination. Do not bind this procedure to
  one named review skill or treat AC validation as a substitute for review.
- Quality review owns only findings and issue persistence. It must not edit repo
  content, mark ACs, write AC evidence, or create a finalization candidate.
- Treat each AC's `Check:` as the default proof path. If it is missing, unsafe,
  ambiguous, or infeasible, record an issue instead of inventing a replacement
  proof path silently.
- Preserve optional AC `Details:` when updating an AC body, and keep `Evidence:`
  last under that AC.
- Treat existing AC evidence, implement-written claims, task notes, and
  candidate verification notes as untrusted until independently reproduced by
  code inspection, diff inspection, or commands.
- Human review is outside AC completion. Successful verification enters
  `Status: review` with `Next: review`.
- Successful verification records a fresh `## Finalization Candidate` before
  entering review.
- When repository changes exist, the finalization candidate must use
  `closeout: finalize-revision` unless the user explicitly requested no VCS
  closeout.
- Use `closeout: none` only when no repository changes exist or the user
  explicitly requested no VCS closeout.
- Finalization candidates contain `closeout` plus only the fields required by
  that closeout mode.
- Remove any existing finalization candidate when verification does not pass.
- External/manual confirmation may remain as `[~]` under an AC only when the
  agent has satisfied it as far as it can.
- Validate by reading code and state, not only by running commands.
- Independently check that changed files, changed behavior, and verification
  commands stay within `## Boundaries`.
- Keep findings scoped to ACs, correctness, safety, maintainability, evidence
  quality, boundaries, or stale/invalidated assumptions.

Steps:

1. Validate `Status: active` and `Next: verify`.
2. Inspect current repo changes and relevant files.
3. Compare every changed file and changed behavior to `## Boundaries`. Add a
   concrete issue for any violation, ambiguous compliance, unverifiable
   discoverable-scope claim, or crossed stop-before condition.
4. Check task annotations. Add a concrete issue for tasks that should trace to
   an AC or issue but do not.
5. For each `(ACN, codify)` task, independently confirm the added or updated
   check exercises the referenced AC. Add a concrete issue when it does not or
   cannot be proven within boundaries.
6. Run an independent quality review of the current changes before AC
   validation. Choose the review mechanism based on the diff and available
   tooling rather than a fixed skill dependency. Review for defects,
   inconsistencies, safety risks, regressions, contract or continuity breaks,
   missing or weak validation, stale supporting artifacts, maintainability
   issues, boundary drift, and artifacts that need artifact-specific scrutiny.
7. Convert actionable review findings into numbered `## Issues`. Deduplicate by
   same file and same concern. Reopen a resolved matching issue when the concern
   still exists. Do not record non-actionable observations where the required
   author action is unclear.
8. If new or reopened review issues exist, remove any existing
   `## Finalization Candidate`, keep `Status: active`, set `Next: implement`,
   and return to the dispatcher. Do not proceed to AC validation until the
   quality review gate is clean.
9. For each non-invalidated AC, follow its `Check:` as the default proof path.
   Run commands, inspections, or manual-confirmation checks as needed within
   boundaries.
10. Check whether current changes weaken, contradict, supersede, or make
    evidence stale for any AC.
11. Record independently reproduced observed results in `Evidence:` directly
    under each AC. Preserve optional `Details:` and keep `Evidence:` last.
12. Mark ACs `[x]` when satisfied with evidence, `[~]` only when satisfied as
    far as the agent can tell but external/manual confirmation is required, and
    `[!]` when contradicted, unsafe, blocked, failed, or missing evidence.
13. Create, update, or close numbered issues based only on independent
    validation. Add open issues for anything that must return to action.
14. If open issues remain or any non-invalidated AC is `[ ]` or `[!]`, remove
    any existing `## Finalization Candidate`, keep `Status: active`, set
    `Next: implement`, and return to the dispatcher.
15. If every non-invalidated AC is `[x]` or `[~]` with evidence and no open
    issues remain, choose the closeout mode authorized by the plan and verified
    state. If repository changes exist and the user did not explicitly request
    no VCS closeout, choose `closeout: finalize-revision`.
16. For `closeout: none`, replace any existing `## Finalization Candidate` with
    a fresh section containing only `closeout: none`. Use this only when no
    repository changes exist or the user explicitly requested no VCS closeout.
17. For `closeout: finalize-revision`, capture the current `@` as
    `target_commit` using read-only jj inspection, such as
    `jj log -r @ --no-graph -T 'commit_id ++ "\n"'`.
18. Draft `revision_description` as a complete proposed jj revision description
    based on the checked diff and state context, following the repository's
    revision-description rules.
19. Assign the exact proposed `revision_description` to a shell variable and
    validate it with `printf '%s\n' "$desc" | commit-message check`. If
    validation fails, revise the proposed description and rerun validation until
    it passes before writing the candidate.
20. Replace any existing `## Finalization Candidate` with a fresh section
    containing only `closeout: finalize-revision`, `target_commit`, and
    `revision_description` in this exact shape:

    ````markdown
    ## Finalization Candidate

    closeout: finalize-revision

    target_commit: <current @ commit id>

    revision_description:
    ```text
    <complete proposed jj revision description>
    ```
    ````

    Do not use YAML block scalars such as `revision_description: |`; the
    revision description must be in the fenced `text` block.

21. Reread the written finalization candidate before entering review. If it does
    not match the documented schema, remove the candidate, keep
    `Status: active`, set `Next: implement`, add or update an issue describing
    the schema mismatch, and stop.
22. Set `Status: review`, set `Next: review`, and stop the active loop.

Reread the state file before returning control to the dispatcher or stopping.
The state file is authoritative.
