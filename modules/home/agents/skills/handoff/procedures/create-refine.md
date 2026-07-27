# Create Or Refine

Creating or refining authorizes only the handoff artifact and the minimum safe
local `.agent/handoffs/` directory and ignore setup. It never authorizes the
work described by the prompt, implementation edits, or revision changes.

## Draft

1. For refinement, resolve an explicit path first, then an exact filename, then
   a unique slug fragment or clear natural-language match below the canonical
   store. Ask the user to choose when multiple artifacts match. For creation or
   non-explicit refinement, resolve the canonical root with
   `lib/resolve-store.sh` as specified by the entry contract.
2. Use the current local time and a concise lowercase kebab-case slug for a new
   `YYYY-MM-DD-HHMMSS-<short-slug>.md`; add a numeric suffix if needed.
3. Identify one explicit or safely inferable next-session operation and its
   intended outcome. Informational goals such as explain, investigate, compare,
   decide, validate, plan, or review are valid. If materially different goals
   remain plausible, ask one focused question and do not write yet.
4. Include semantic content rather than empty or rigid sections:
   - Purpose: the single operation and intended outcome.
   - First Action: one concrete action after the receiver orients itself.
   - Scope: included work and material exclusions.
   - Constraints: authority, safety, compatibility, and behavioral invariants.
   - Authoritative Inputs: changing artifacts the receiver must reload.
   - Validation: observable completion conditions.
5. Add current state, decisions, rejected approaches, assumptions, unknowns,
   blockers, risks, or response guidance only when they materially help the
   receiver. Produce an actionable prompt, not a transcript or passive archive.
6. Verify checkable paths, filenames, symbols, revisions, repository state,
   completed-work claims, and reported validation results with direct reads,
   searches, or appropriate Git/jj inspection. Rerun checks only when safe,
   proportionate, local, and within drafting authority. Mark material claims
   unverified when confirmation is unavailable, unsafe, costly, or out of scope.
   Do not start fresh implementation or unrelated research to fill the prompt.
7. For refinement, reread the complete artifact immediately before editing and
   treat it as authoritative over remembered conversation. Rewrite the
   self-contained current-best prompt rather than appending chronology. Preserve
   compatible direct user edits; ask one targeted question before overwriting
   unexplained conflicting edits.

## Store Safely

Before writing, inspect the canonical store, local ignore file, and target. Do
not require a clean working copy and do not alter unrelated state.

1. Stop if `.agent/handoffs`, its `.gitignore`, or the target is tracked. Stop
   if safe verification would require untracking a path or changing a tracked
   ignore file.
2. If `.agent/handoffs/.gitignore` exists, proceed only when its ownership and
   contents are compatible with a self-ignoring local store containing the `*`
   pattern. Never overwrite it. Otherwise create the directory and a local
   `.gitignore` containing `*`.
3. For a new handoff, create a temporary representative in the store. Verify the
   ignore file and probe are ignored and untracked, then remove the probe.
   Verify an existing refinement target directly.
4. In Git or colocated Git/jj repositories, use Git tracking and ignore checks
   plus read-only `jj --ignore-working-copy file list` inspection when jj is
   present. Do not force a jj snapshot solely to prove ignored new files stay
   absent. In non-Git jj repositories, use a safe snapshot and targeted
   `jj file list` inspection to prove both paths remain absent.
5. Write the complete artifact, then repeat the applicable ignore, tracking, and
   snapshot checks for its actual path. Stop rather than changing storage or
   tracked files to bypass a failure.

## Report

Report the absolute path, purpose and goal, material unresolved questions, and
the intended next action. Do not claim that the described task ran. Then provide
this canonical paste-ready execution prompt in chat, substituting the absolute
path; never embed it in the artifact:

```text
Execute <absolute-handoff-path>. Read it in full, reload its Authoritative Inputs, reconcile material drift immediately before mutation, and complete the task. Stop and ask me if drift invalidates the goal, scope, authority, or required assumptions.
```
