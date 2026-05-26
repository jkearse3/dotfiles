---
name: investigate
description: Investigate a topic and return structured findings <topic>
argument-hint: "<topic>"
---

# Investigate

Investigate a topic using parallel subagents and return a structured report.

## Arguments

```
$ARGUMENTS
```

Required: a topic or question to investigate.

If no topic provided, stop and say: "Usage: /investigate <topic>"

## Execution

Take the user-provided topic from the Arguments block as the topic. Review conversation context for
what is already known — avoid re-investigating settled questions.

### Dispatch

Entry point — used only for the initial investigation. Default to a single subagent. Only decompose
into sub-topics when the topic has genuinely independent areas that cannot be explored sequentially:

- Most topics: dispatch a single subagent with the topic itself
- Broad, multi-faceted topics with independent sub-areas: 2-3 focused sub-topics (max)
- Dependent questions (where one answer feeds another): always merge into a single sub-topic

Prefer fewer subagents — each one carries system context overhead. A single thorough investigation
beats multiple shallow ones.

Dispatch subagents in the same message (parallel dispatch):

- Dispatch a subagent with a prompt composed from the sub-topic (with relevant conversation
  context), the `## Research Brief` section, and the `## Output Format` section below. Paste both
  sections wholesale into the prompt.

If a subagent fails or returns no structured results, note its sub-topic as an unresolved question.

Then proceed to **Synthesize**.

### Synthesize

Merge subagent results into a single report. Synthesize related findings, reconcile conflicts with
evidence from both sides, and filter out what is already known from conversation context. Order
findings so prerequisites appear before things that depend on them — the reader should encounter
each concept only after its foundations have been laid.

**Evidence scrutiny** — before including each finding, check its sources:

- Finding has a concrete source (`file:line`, URL, specific doc reference) → include as finding
- Finding has no source or only vague attribution ("the code", "the docs", "the codebase") → demote
  to lead with a note about what evidence is missing
- Finding cites a source but the reference is imprecise (e.g., file path without line number,
  "somewhere in the config") → include as finding but note the imprecise source

The Summary should synthesize across all sub-topics — not just concatenate.

Produce a draft report using the `## Output Format` section below, then proceed to **Follow-up**.

### Follow-up

After the initial synthesis, review the draft report's Questions and Leads sections to identify
gaps.

1. **Classify gaps**: For each question or lead, determine whether it is investigable (a targeted
   search could resolve it) or terminal (no available tool or source can answer it).
2. **Dispatch targeted subagents**: For each investigable gap, dispatch a subagent with a prompt
   composed from the specific question or lead, relevant context from the initial findings, the
   `## Research Brief` section, and the `## Output Format` section. Dispatch all targeted subagents
   in parallel.
3. **Re-synthesize**: Merge follow-up results into the existing draft — promote confirmed leads to
   findings, resolve questions, update the summary. Apply the same evidence scrutiny and dependency
   ordering as the initial synthesis.
4. **Converge**: If any gaps were resolved in this round, return to step 1 with the updated draft.
   If no gaps were resolved (all remaining gaps are terminal or follow-up produced no new
   information), the report is final.

Terminal gaps remain in the Questions section of the final report. Do not remove them.

## Output Format

Use this exact format for the final report:

```
## Research: <topic>

### Findings
- <finding with evidence>
  - <supporting detail if needed>
  - src: <URL or doc reference>
  - ref: `path/to/file.ext:line` — <what's relevant>

### Leads
- <plausible direction worth following up>
  - What would confirm or refute: <validation approach>
  - ref: `path/to/file.ext:line` — <what suggested this>

### Questions
- [ ] <unresolved question>
  - src: <source that prompted this, if applicable>

### Assumptions
- [ ] <assumption and basis>
  - ref: `path/to/file.ext:line` — <what informed this>

### Summary
<direct answer to the question>
```

**Section rules:**

- **Summary**: Direct answer to the topic. Should stand alone as a useful answer. Be concrete and
  opinionated where evidence supports it.
- **Findings**: Facts discovered with source/evidence. Each finding should be independently useful.
  - Use bullet list items (not numbered) — sub-items allowed for supporting detail
  - State what was found, not just where
  - Every finding must have at least one source sub-bullet (mandatory)
  - Use `src:` prefix for web URLs and documentation references
  - Use `ref:` prefix for file paths and line numbers
- **Leads**: Plausible directions or hypotheses that lack direct evidence. Not findings — these are
  worth following up but unconfirmed.
  - State the hypothesis and what prompted it
  - Include what would confirm or refute it
  - Attribute with source sub-bullets (encouraged, not mandatory)
- **Questions**: Things that remain unanswered after investigation.
  - Attribute with source sub-bullets when a specific source prompted the question (encouraged, not
    mandatory)
- **Assumptions**: Beliefs formed during investigation that lack direct evidence.
  - `[ ]` for unvalidated assumptions (default)
  - `[~]` for accepted working assumptions (investigated across multiple passes or confirmed by user
    without direct validation — reasonable to proceed with)
  - State what the assumption is and why it seems reasonable
  - Note what would validate or invalidate it
  - Attribute with source sub-bullets when a specific source informed the assumption (encouraged,
    not mandatory)

## Research Brief

Investigation instructions for subagents. Paste this section wholesale into subagent prompts.

---

Investigate your assigned topic using available tools. Return structured findings.

**How to investigate:**

- Start broad, narrow down as you learn
- Run independent searches in parallel where possible
- Follow new leads that stay within scope
- Trace motivations — why does this exist, what problem does it solve
- Map connections — how does this relate to surrounding context
- Stop when the topic is sufficiently answered or all leads are exhausted

**Rules:**

- Stay focused on the stated topic. Do not expand scope.
- Ground claims in concrete evidence.
- If the topic is too broad, narrow to the most relevant aspects and note what was excluded.
- Do not modify any files. This investigation is read-only.
- Do not create objectives or update existing ones.

**Evidence requirements:**

- Every finding must have a concrete source: `file:line`, URL, or specific doc reference.
- A claim without a concrete source is not a finding — either locate the source or demote to the
  Leads section.
- Clearly distinguish **verified facts** (confirmed via code, docs, or direct evidence) from
  **leads** (plausible directions worth following up). Leads are hypotheses, not findings — place
  them in the Leads section (not Findings) and state what would confirm or refute each one.

**Before returning**, re-verify your key claims:

1. Re-read the relevant code or docs for your most important findings.
2. Confirm that file paths and line numbers are accurate (not stale from earlier in the
   investigation).
3. If a claim can't be re-verified, move it from Findings to Leads.
