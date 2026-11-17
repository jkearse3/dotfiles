# Findings

Review exists to stop a change from hurting someone after it merges. A finding
names who gets hurt, how, and the real path that gets there: normal use,
real-world input, a real failure, or an attacker at a trust boundary. A
contrived input or a hypothetical future edit is not a real path, except that a
future edit breaking unprotected behavior counts under question 2's rule on
checks. A real path that is rare across the workload it serves and whose harm
the user would notice and could undo is not a finding either; a rare path that
loses data, gives a silently wrong result, or causes harm question 3 names still
is. Report only defects that answer one of these questions:

1. **Does it do what was asked?** A criterion the target misses or only partly
   meets.
2. **Does it work, and does everything else still work?**
   - The new behavior gives the right result on every real path, reports its
     failures rather than hiding them or passing them off as success, and is
     fast enough for its real workload. Work that grows with real data on a
     frequent or large-scale path counts; a path that could merely be faster
     does not.
   - Callers, configuration, keys, and stored data that worked before keep
     working, and no setting silently stops doing anything.
   - Behavior that criteria, other code, users, or stored data depend on, and
     failure paths that would lose data or give silently wrong results, have a
     check that fails when they break. Checks need not catch every possible
     edit.
3. **Is it safe?** A security hole, leaked secrets or personal data, a
   destructive or surprising side effect, including an action nobody approved
   that a user, system, or agent following instructions takes, or permissions
   wider than needed.
4. **Does its text hold up for a reader who has only the codebase?** Comments,
   docs, help text, names, prompts, skills, and descriptions, in the diff or
   elsewhere in the repository, that state something false, and text that only
   makes sense with context outside the repository, such as planning labels or
   references to the session that produced it. Tracker references, such as
   ticket IDs, are fine.
5. **Can it land?** A failing build or check; when reviewed per revision, a
   revision that relies on a descendant to build, pass its checks, or keep its
   parent's interfaces and persisted state usable, unless a decision accepts a
   breaking change it declares; a description that does not account for its diff
   or breaks `finalize-changes`' `references/revision-descriptions.md`; when
   reviewed as a whole, a material mismatch with the stated intent.

Nothing else is a finding: style the repository's tooling does not enforce,
refactoring and reuse ideas, duplication, dead code for its own sake,
optimizations the workload does not need, and advice to "consider".

Judge each artifact the way its consumer uses it: code by what it does when it
runs, and text by what a reasonable reader does after reading it in context. A
finding about text quotes it and names the wrong action or belief it causes; a
reading the surrounding text resolves is not a finding.

A decision settles what it decides, not consequences it shows no sign of having
weighed. Declaring a lost guarantee or breaking change discloses it; only a
decision accepts it. Report harm no decision accepts, and any correction that
would override a decision or undo declared intent, as a `question` asking for
that decision. A suspected defect the evidence cannot settle is a `question`
naming the evidence that would settle it.

## Root Cause

Name each defect's **root cause**: the guarantee the code lacks, such as "every
loop path either makes progress or asks", not just the path that broke. Check
every path in the target that guarantee should cover; each one that fails joins
the finding's **path set**. Defects that share a missing guarantee are one
finding. When earlier findings keep recurring in one component, or several
defects stem from its structure, so that a simpler structure would remove them,
report one finding proposing that structure, with those defects as its path set.

## Correction

Give the smallest change that fixes the root cause, never a workaround that
hides the symptom, such as special-casing one input, swallowing an error,
retrying, or checking downstream of where the bad state arises. When text claims
more than the code enforces and nothing relies on the broader claim, narrowing
the text is the fix. A text correction uses the simplest language that works and
replaces or shortens text rather than appending, keeping each rule in one place.
The correction stays within the code the target changes or made inconsistent,
plus checks for its behavior. When the root fix needs more, such as code outside
the target or a changed external contract, the finding is `design`: state the
real fix and what it touches, the contained workaround and the risk it leaves,
and whether the approach itself needs rethinking.

## Shape

Categorize each finding by the question it answers: `requirement` (1), `bug`,
`regression`, or `coverage` (2), `safety` (3), `text` (4), or `landing` (5); or
`design` or `question` as above. Give its location, category, trigger,
mechanism, path set, root cause, owning revision (the earliest target revision
whose diff introduces it), correction, and decisive evidence.
