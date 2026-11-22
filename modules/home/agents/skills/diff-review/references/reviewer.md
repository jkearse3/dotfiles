# Reviewer

Review a finalized target for defects and assess its declared criteria. The
caller gives you the target's commit IDs and the review inputs, and sets your
read-only boundary. Read `findings.md` beside this file first; it defines what
to report and how.

Read the revisions oldest first. For generated or vendored files, confirm the
output follows its source instead of reading every line. Then trace the target.

## Trace

1. **List the behaviors** the target adds, changes, or removes: commands, keys,
   APIs, config, data formats, outputs, failure handling, and the claims its
   text makes. For each mechanism it replaces or removes, also list the
   guarantees the old one gave, including implicit ones such as validation,
   permission scope, error reporting, and ordering.
2. **Trace each behavior** from every trigger to what a user, caller, or system
   observes, comparing with the base where behavior changed. Find triggers by
   searching for every reference to each name the target adds, changes, or
   removes: callers, bindings, hooks, config, environment, and prose. Also
   consider the privileges and platform it runs under and the other parts of the
   change it interacts with.
3. **Ask each `findings.md` blocker type of each behavior.** Defects commonly
   hide here:
   - `behavior`: a result, such as a return value, error, or exit status, that
     no reader handles, or a failure that looks like the success or absence it
     resembles; a loop, retry, or long-running process with a path that never
     ends or makes no progress; a guard sibling code has that the changed code
     lacks; a state the target's types admit that a consumer mishandles or
     silently defaults on; uniqueness or a cross-record reference enforced only
     in application code, which concurrent writers race past.
   - `coverage`: a mock or fake offered as proof that code works with an
     external system, when it only restates the code's own assumptions.
   - `safety`: an allowlist, access rule, or privilege judged by the use it was
     written for rather than the widest input it admits; credentials, personal
     data, or license-restricted material in the diff; a check that reads or
     changes production, shared, or other non-disposable state.
   - `landing` and `text`: run
     `printf '%s\n' "$desc" | commit-message validate --require-body --conventional`
     on each description, dropping `--conventional` when repository docs define
     their own format, and judge the rules it cannot check by reading.
4. **Load `dependencies.md`** beside this file when the target changes a
   dependency version, lockfile, or package source.

Cover every behavior even after finding a defect.

## Evidence and Checks

Prefer what the trace gathered, then admissible check evidence, before running a
check. A check evidence entry is admissible for a revision whose tree equals the
entry's commit (`jj diff --from <entry> --to <rev>` is empty). Run a check only
to settle a suspected defect or decide a criterion, except tip checks: when
requested, run the repository's checks at the target's tip and report each
failure as a candidate owned by the revision that causes it. A criterion whose
only decisive check would leave persistent state is `blocked`, naming that
check.

Report an earlier finding again only if it still holds. A declined candidate
stays declined unless you find new evidence that answers its decline, in which
case raise it as a candidate with that evidence.

## Return

- **Coverage:** granularity, behaviors traced, unreached areas with the missing
  evidence, references loaded, check evidence admitted and ignored, known issues
  the target neither introduces nor worsens, and declined candidates that stay
  declined.
- **Criteria:** each `satisfied`, `not satisfied`, or `blocked`, with evidence.
- **Candidates:** in the `findings.md` shape, only those your evidence shows are
  blockers the verifier will confirm; drop one you expect it to decline. A
  suspected blocker you cannot settle is a candidate only when `findings.md`
  would make it a `question`.
