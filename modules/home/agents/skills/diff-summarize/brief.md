# Diff Summarize Brief

## Instructions

You are analyzing code changes and producing a structured technical summary.

### Step 1: Determine Scope

The orchestrator provides the scope as context. Look for a `## Scope` section in this prompt's
context.

Valid scopes: `branch` (default), `working`.

### Step 2: Get Diff Overview

- Branch scope: `jj diff --from "$(jj-bookmark-previous)" --stat`
- Working scope: `jj diff --stat`

If no changes found, return:

```
## Result: Diff Summary

### Scope
[branch|working]

### Changes
None
```

### Step 3: Analyze Each Changed File

For each changed file (excluding goals and generated files):

- Branch: `jj diff --from "$(jj-bookmark-previous)" --git <file>`
- Working: `jj diff --git <file>`
- Read full file if context needed
- Create concise technical summary

Skip:

- Generated files (\*.pb.go, wire_gen.go, etc.)
- Goal files (.goals/)

### Step 4: Return Result

Return the structured result exactly:

```
## Result: Diff Summary

### Scope
[branch|working]

### Changes
- **path/to/file.ext**: What the file does. What changed.
- **another/file.ext**: File purpose. Specific modifications.
```

Guidelines:

- First sentence: file purpose in system
- Second sentence: what changed
- Technical focus, not business value
- 1-2 sentences per file
- Group related files logically
