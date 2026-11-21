---
name: verify
description: >-
  Gathers focused evidence about an outcome and writes a local HTML report, even
  when blocked. Use when the user directly asks to verify behavior, such as
  “check that the invite flow works” or “confirm the fix.” Not for routine
  checks Pi initiates on its own during implementation.
---

# Verify

In Pi, `/skill:verify` is an optional shortcut. Verify behavior; don't fix it.

## Check the requested behavior

1. Establish the scope, environment, starting state, and expected observable
   results before running checks. Clarify missing expectations rather than
   deriving them from what the system happens to do. Use disposable data in a
   local or test environment, not production or real user data.
2. Use the available tooling that can directly check the requested outcome.
   Reuse the project’s verification tools when they cover it. If no available
   tool can check it, report what was blocked. Keep test state isolated. Collect
   useful evidence, such as a screenshot for a visual result or a trace that
   explains the sequence. Clean up only resources created for this run, even on
   failure.
3. Compare each observation with its expectation. Mark it **Passed** if the
   observation matches (including an expected error), **Failed** if it
   contradicts the expectation, or **Not checked** if you could not observe the
   result. Name the blocker for each unchecked result. If a mismatch prevents
   later observations, mark the mismatch **Failed** and the unreached checks
   **Not checked**.

## Write the report

Every explicit run produces `verification.html`, even if nothing could run. Copy
the bundled [report template](report-template.html), replace its placeholders,
and keep its layout and styles. Include the scope, environment, starting state,
and totals for all three statuses. Repeat the check block for each expectation,
keeping only its matching badge. In the collapsed details, record the commands
or actions actually run and enough setup to repeat them. If none ran, say so and
name the unmet prerequisite; do not present proposed steps as executed.

Put the report and any evidence in the same per-run temporary directory outside
the repository, not in scratch that gets swept on agent exit. Collect only the
evidence needed for the report and save it before cleanup. Link only sanitized
files in that directory using relative paths and associate them with the checks
they support; give screenshots descriptive alt text. Leave the no-evidence
message if there are no safe supporting files. Keep secrets and personal data
out of the report, commands it quotes, and artifacts. Escape text and attribute
values; do not insert raw markup from the system or logs. No server or external
assets are needed to read the report.

After cleanup, check that each relative evidence file is still readable from
disk. Preview the report offline with an available renderer that can open
`file://` URLs. Do not open a visible window by default. If no suitable renderer
is available or the preview fails, say that rendering was not checked. Say which
evidence files, if any, could not be read.

If the report was saved, return a brief result, a clickable Markdown `file:///`
link to the report, and the literal absolute path separately in inline code so
it can be copied. Percent-encode characters as needed in the URI, not in the
copyable path. For example:

```markdown
[Open report](file:///tmp/verify%20%231/verification.html)

`/tmp/verify #1/verification.html`
```

If the report could not be saved, explain why instead of returning a link or
path to a nonexistent report.
