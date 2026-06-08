# Phase Iterate Results

Caller-parsed result blocks returned by `procedures/phase-iterate.md --auto-commit`.

## Phase Iterate Result Blocks

`procedures/phase-iterate.md --auto-commit` returns one of these caller-consumed blocks. Callers
must preserve token matching, field order, and field meanings exactly.

Incomplete result:

```text
PHASE_INCOMPLETE
phase: <N>
reason: <blocked_tasks|unresolved_issues|implement_concerns>
details: <specific blockers or concerns>
```

Meanings:

- `PHASE_INCOMPLETE` — phase iteration stopped before commit because user-visible follow-up is
  required.
- `phase` — focused phase number.
- `reason` — machine-readable stop category; keep values limited to the listed tokens.
- `details` — human-readable blockers, unresolved issues, or implementation concerns.

Complete result:

```text
PHASE_COMPLETE
phase: <N>
commit_message: <the full revision description used>
ac_status: <list of AC number and new status, e.g. "AC1: [~], AC3: [~]">
```

Meanings:

- `PHASE_COMPLETE` — phase changes were committed and the phase index was marked complete.
- `phase` — completed phase number.
- `commit_message` — exact full revision description passed to `jj commit -m`.
- `ac_status` — latest AC status snapshot captured by phase iteration for targeted ACs.
