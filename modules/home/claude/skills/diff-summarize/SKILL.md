---
name: diff-summarize
description: Summarizes code changes with file-by-file technical details. Use for PR descriptions or understanding what changed.
argument-hint: "[branch|working]"
---

# Diff Summarize

Orchestrator — validates arguments and dispatches a Task subagent to analyze code changes.

## Arguments

```
$ARGUMENTS
```

Valid scopes: `branch` (default), `working`, or empty.

**Validation**: If `$ARGUMENTS` is not empty and not one of `branch` or `working`, report error and
stop:

```
Error: Invalid scope "$ARGUMENTS". Valid options: branch, working
```

## Execution

1. **Determine scope**: Use `$ARGUMENTS` if provided, otherwise default to `branch`.

2. **Dispatch subagent**: Use the `Task` tool with `subagent_type: "general-purpose"` and prompt:

   ```
   Read the file at ~/.claude/skills/diff-summarize/brief.md and execute the instructions within it.

   ## Scope
   <scope>
   ```

   Replace `<scope>` with the determined scope (`branch` or `working`).

3. **Return result**: Return the subagent's result as-is.
