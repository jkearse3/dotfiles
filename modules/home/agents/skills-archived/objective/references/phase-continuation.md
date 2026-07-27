# Phase Continuation

Continuation labels and schema for phase-local resume state.

## Continuation Schema

When present, `### Continuation` uses this minimal schema:

```markdown
### Continuation

Status: <status token>
Source: <where the continuation was created>
Route: <procedure or step to resume>
Summary: <one-paragraph resume context>
Clear when: <condition that makes the next resume point unambiguous>

#### Payload

[Optional structured details needed by the routed procedure]
```

`#### Payload` is optional. Omit it when the fixed labels provide enough resume
context.
