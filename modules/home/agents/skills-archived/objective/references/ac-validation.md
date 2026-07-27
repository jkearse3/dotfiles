# AC Validation

Acceptance-criterion validation and status derivation for phase verification.

## AC Validation And Derivation

Use this operation when a verify brief decides whether phase changes satisfy
objective ACs and writes marker/evidence updates back to `00-main.md`.

Inputs:

- `## Acceptance Criteria` from `00-main.md`.
- Phase `### Tasks`, including `(ACN, satisfy)` and `(ACN, enhance)`
  annotations.
- Completed task context and changed code for the current phase.

Apply validation:

1. Identify relevant code from completed phase tasks and changed files.
2. Inspect the implementation directly; validate by reading code, not just by
   running tests.
3. Treat tests as supporting evidence. Cite existing tests when they cover the
   behavior.
4. Select the AC marker from `references/ac-markers.md` § AC States based on
   observed satisfaction and confidence.
5. Record concise evidence per `references/ac-markers.md` § AC Validation
   Evidence for every AC moved to `[~]` or `[x]`.

Apply derivation for ACs targeted by phase tasks:

1. If all references for an AC are `(ACN, enhance)`, preserve the existing
   marker, text, annotations, and evidence; enhancement work does not change
   satisfaction status by itself.
2. If the phase task carries a `(human)` annotation for the AC, preserve the AC
   marker, text, and `(human)` annotation. Do not replace human validation with
   code validation.
3. If a `(ACN, satisfy)` task references an AC that does not exist in
   `00-main.md`, flag a readiness issue in the phase file instead of creating an
   AC silently.
4. For matching `(ACN, satisfy)` tasks, derive the AC marker from validation and
   add evidence notes for `[~]` or `[x]` results.

Write `## Acceptance Criteria` in a single edit after derivation. Preserve
existing AC text and `(human)` annotations, update only derived markers and
evidence notes for ACs assessed by the verify brief, and include all derived AC
statuses in the verify summary.
