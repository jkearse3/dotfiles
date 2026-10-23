---
name: ticket
description: >-
  Writes a tracker-agnostic ticket, with a title, problem, solution, and
  acceptance criteria, from a request, note, thread, conversation, or `shape`
  spec. Use when the user asks to write, draft, or turn something into a ticket,
  issue, or story. Not for shaping an unclear change (use shape), PR text (use
  pull-request), or creating or updating issues in a tracker.
---

# Ticket

Turn work that needs doing into a ticket a teammate can read in under a minute
and act on without a follow-up conversation. Keep the same shape whatever the
destination tracker. Writing a ticket is read-only and authorizes no tracker
mutation or implementation.

## Input

Take the work to ticket from the user's request and the surrounding context, in
whatever form it arrives: a sentence, note, bug report, Slack thread, error,
conversation, or `shape` spec. Draw from it the goal, constraints, exclusions,
decisions, and links, and keep their wording. Ask only if the subject is absent
or could mean materially different work.

## Method

1. **Ground lightly.** Inspect only what you need to state the problem
   accurately and to point the implementer in the right direction: the relevant
   files, symbols, errors, or linked sources. Separate what you observed from
   what you inferred. When a `shape` spec is the input, treat it as already
   grounded and condense it instead of reinvestigating.
2. **Check readiness.** A ticket needs a real problem and a credible direction.
   When the problem is unclear, the input proposes a fix for a symptom, or
   several materially different solutions remain open with no basis to choose,
   say so in a sentence and recommend `shape` before ticketing. When the user
   wants the ticket anyway, write it with the solution marked as proposed and
   the open choices under `Open Questions`.
3. **Check size.** When the work contains several separately shippable outcomes,
   propose a split into one ticket per outcome, and ask before writing several
   tickets.
4. **Write.** Compose the ticket following the format below. Ground every
   material claim in the input or in inspected evidence. Never manufacture
   motivation, urgency, or impact.
5. **Reread as the assignee.** Holding only the ticket and its links, a reader
   must be able to say what is wrong, what is decided, what is excluded, and how
   to know it is done. Cut anything that does not help that reader.

## Format

Return the ticket as a single Markdown block, with the title on the first line
as a level-one heading, so it can be pasted or passed to a tracker as is.

```markdown
# <Title>

## Problem

<What is wrong or missing today, who or what it affects, and why it matters.>

## Solution

<The approach, at the level a reviewer would agree or disagree with.>

## Acceptance Criteria

- [ ] <Observable result that shows the problem is solved.>
- [ ] <Invariant that must still hold.>

## Out of Scope

- <Adjacent work this ticket deliberately excludes.>

## Implementation Notes

- <Pointer that saves the implementer time.>

## Context

- <Link and what it provides.>

## Open Questions

- <Unresolved decision, its owner when known, and what it blocks.>
```

`Problem`, `Solution`, and `Acceptance Criteria` are required. Include the other
sections only when they have content, in the order shown. Never write `None` or
`N/A` placeholders.

### Title

Write a concise imperative statement of the outcome:

```text
Prevent duplicate invoice emails on retry
Show the sync error when a calendar import fails
Upgrade the API service to Node 24
```

Do not name the symptom ("Duplicate emails bug") or the activity ("Look into
invoice emails"). Do not add a type, area, or ticket-ID prefix; tracker fields
carry those.

### Problem

Write one or two short paragraphs. Lead with current behavior or the missing
capability, then who or what it affects and why it matters now. For a bug, add
the steps to reproduce, the expected result, and the actual result:

```markdown
**Steps to reproduce**

1. <Step>

**Expected:** <result>

**Actual:** <result>
```

For routine work such as an upgrade or cleanup, one sentence of purpose is
enough.

### Solution

State what is decided: the approach and, when it is not obvious, why it was
chosen over the alternative. Stop at the level of detail that someone could
disagree with. Leave step-by-step instructions to `Implementation Notes` or to
the implementer. When the direction is not settled, begin with "Proposed:" and
list the open choices under `Open Questions`.

### Acceptance Criteria

Write each criterion as a checkbox with an observable result, such as "Retrying
a failed charge sends exactly one invoice email," not an activity such as "Add
an idempotency key." Derive criteria from the problem, not from the solution, so
that a different valid implementation still satisfies them. Include an invariant
only when breaking it is a credible risk. Keep the list short. When it grows
past about seven items, check whether the ticket should be split.

For a spike or investigation, the criteria are the questions answered and the
deliverable, such as "Recommendation written up and linked in this ticket."

### Optional Sections

- **Out of Scope:** adjacent work a reasonable reader might expect to be
  included, and which the ticket does not cover.
- **Implementation Notes:** files and symbols, gotchas, constraints, and prior
  art that grounding established. Write them as hints, not instructions. Name a
  path or symbol only when you inspected it.
- **Context:** links to threads, errors, dashboards, related tickets and PRs,
  and documents, each with a few words on what it provides. Put background
  explanation in `Problem`, not here.
- **Open Questions:** decisions the ticket cannot settle. Keep them out of the
  other sections.

## Output

Return the ticket block in the response. After it, note in a line or two any
assumption the ticket relies on that the user should confirm. Do not take any
further step unasked.

## Boundaries

- Do not create, update, or comment on issues in Linear, Jira, GitHub, or any
  other tracker. The user hands the ticket to a tracker separately.
- Do not set or propose tracker metadata such as priority, estimate, labels,
  assignee, cycle, or project in the ticket body.
- Do not edit files, mutate version control, or implement the work.
- Do not expose agent procedures, internal workflow names, or unverified claims
  in ticket text.
