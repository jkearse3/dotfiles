# Findings

Review exists to stop a change from becoming a liability once it merges. Report
only blockers: defects that hurt someone on a real path, meaning normal use,
real-world input, a real failure, or an attacker at a trust boundary, never a
contrived input. A finding names who gets hurt, how, and that path. The diff
need not be perfect.

## Blocker Types

- `landing`: a build, test, lint, or `commit-message validate` check fails; a
  declared criterion is missed or only partly met; the target makes visible, as
  the Alignment rule defines it, something a declared complete list of what it
  may make visible does not call for; when reviewed per revision, a revision
  relies on a later one to build, pass its checks, or keep working, unless a
  decision accepts a breaking change the revision declares; when reviewed as a
  whole, a material mismatch with the stated intent.
- `behavior`: a wrong result, lost or corrupted data, a crash or hang, a failure
  hidden or reported as success, or something that worked before breaking, such
  as a caller, configuration key, or stored data.
- `performance`: on work that grows with real data, an obvious avoidable fault,
  such as unbatched calls, avoidable quadratic or worse time or space, repeated
  work that could be done once, or loading everything where streaming or paging
  fits; not micro-optimizations or speedups the workload does not need.
- `coverage`: behavior that criteria, callers, users, or stored data rely on, or
  a failure path that would lose data or give a silently wrong result, has no
  check that fails when it breaks. Checks need not catch every possible edit.
- `safety`: a security hole, leaked secrets or personal data, permissions wider
  than needed, or a destructive, surprising, or unapproved side effect,
  including one a user, system, or agent takes by following the target's text.
- `text`: a false statement in a description, doc, comment, help text, skill, or
  prompt, in the diff or elsewhere that the diff made false; a description that
  does not account for its diff or breaks `finalize-changes`'
  `references/revision-descriptions.md`; a name whose plain reading misstates
  its meaning, omits a unit its type lacks, leaves a boolean's true case
  unclear, or no longer matches behavior; text that only makes sense with
  context outside the repository, such as planning labels or references to the
  session that produced it. Tracker references, such as ticket IDs, are fine.

Nothing else is a finding: style the repository's tooling does not enforce,
preferring another accurate name, refactoring and reuse ideas, duplication, dead
code for its own sake, a path rare across its workload whose harm the user would
notice and could undo, and advice to "consider".

Judge each artifact the way its consumer uses it: code by what it does when it
runs, and text by what a reasonable reader does after reading it in context. A
`text` finding quotes the text and names the wrong action or belief a reader
following it would take; an ambiguity the surrounding text resolves, or a gap a
competent agent would fill sensibly, is not a finding, but a false claim or a
description that breaks its rules is, however inconsequential it seems.

A decision settles what it decides, not consequences it shows no sign of having
weighed. Declaring a lost guarantee or breaking change discloses it; only a
decision accepts it. Report harm no decision accepts, and any correction that
would override a decision or undo declared intent, as a `question` asking for
that decision. Report a suspected blocker the evidence cannot settle as a
`question` naming the evidence that would settle it only when its harm would be
irreversible, such as lost data, a security hole, or broken history; otherwise
drop it.

## Root Cause

Name each defect's **root cause**: the guarantee the code lacks, such as "every
loop path either makes progress or asks", not just the path that broke. Check
every path in the target that guarantee should cover; each one that fails joins
the finding's **path set**. Defects that share a missing guarantee are one
finding. When earlier findings keep recurring in one component, several defects
stem from its structure, or defects arise in what corrections of earlier
findings added, and a simpler structure would remove them, report one finding
proposing that structure, with those defects as its path set; it may drop
mechanism added for earlier findings that no longer count or that it resolves.

## Correction

Give the smallest change that fixes the root cause, never a workaround that
hides the symptom, including a check downstream of where the bad state arises.
When text claims more than the code enforces and nothing relies on the broader
claim, narrowing the text is the fix. A text correction replaces or shortens
text rather than appending, and one to agent text follows `skill-style`. The
correction stays within the code the target changes or made inconsistent, plus
checks for its behavior. When the root fix needs more, such as code outside the
target or a changed external contract, the finding is `design`: state the real
fix and what it touches, the contained workaround and the risk it leaves, and
whether the approach itself needs rethinking.

## Shape

Categorize each finding by its blocker type, or as `design` or `question` as
above. Give its location, category, trigger, mechanism, path set, root cause,
owning revision (the earliest target revision whose diff introduces it),
correction, and decisive evidence.
