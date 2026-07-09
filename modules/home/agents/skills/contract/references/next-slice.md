# Next Slice Guidance

Keep `## Next Slice` useful as a manual implementation handoff. `## Next Slice` describes the next
implementation slice; it is not permission for this skill to make inline repository implementation
edits. It must be consistent with `## Implementation Approach`, `## Boundaries`, and
`## Validation`.

When work remains, `## Next Slice` names the next reviewable implementation-ready slice that
advances unsatisfied or partial ACs while staying independently verifiable. Prefer a slice with one
primary review question. Do not choose a slice that mixes unrelated risk areas unless separating
them would create artificial scaffolding or make the result harder to verify. Slice by reviewable
risk area and user-visible behavior, not by maximum size, estimated size, file count, task count, or
the smallest possible change.

Use this pattern:

```markdown
Make the next reviewable change that advances the next unsatisfied acceptance criteria.

Target AC: <number or numbers>

Do this by <specific implementation boundary>.

Stop before <nearest ambiguity, unrelated behavior, or agreement change>.

Verify with <cheap check or inspection>.
```

The slice should include:

- Target AC numbers.
- A specific implementation boundary.
- The nearest stop-before condition.
- A cheap verification path.

Do not add size labels, time estimates, task queues, or mechanical file-by-file checklists. A slice
is probably too broad if review would need to answer several unrelated questions at once. Narrow it
until the slice has one primary reason to exist and one clear verification path.

When no implementation work remains, say that no implementation slice is pending and identify the
next useful reconciliation or user-decision step.

Describe handoffs as user intents, not literal command examples. A typical manual loop is: reconcile
the branch contract, perform the next slice with whatever implementation workflow the user chooses,
then reconcile the branch contract again.

The contract skill does not write workflow state files, coordinate implementation work, commit,
describe, split, squash, switch bookmarks or branches, push, or move work between revisions.
