# Phase Verify Results

Caller-parsed result blocks for the phase verify brief.

## Verify Summary Result Blocks

Headings and fields are caller-parsed — do not rename or reorder.

No changes:

```text
## Result: Verify Summary

No changes to verify.
```

Review gate with new issues:

```text
## Result: Verify Summary

### New Issues
- [count by severity, or "None"]

### Total Open Issues
- [count remaining [ ], or "None"]

### Recommendation
- [address high-severity issues before next cycle]
```

Full summary:

```text
## Result: Verify Summary

### Review
- Issues: [count new issues, or "Clean -- no issues found"]

### Validated
- [list of ACs now [x], or "None"]

### Needs Verification
- [list of [~] ACs with explanation, or "None"]

### Regressions
- [list of [!] ACs with explanation, or "None"]

### Not Implemented
- [list of remaining [ ] ACs, or "None"]
```

## AC Status Mapping

Consumers that parse AC validation results derive `ac_status` from these
sections:

| Verify section           | Status |
| ------------------------ | ------ |
| `### Validated`          | `[x]`  |
| `### Needs Verification` | `[~]`  |
| `### Regressions`        | `[!]`  |
| `### Not Implemented`    | `[ ]`  |
