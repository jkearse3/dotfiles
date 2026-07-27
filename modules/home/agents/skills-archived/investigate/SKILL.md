---
name: investigate
description:
  Investigates open-ended questions, unfamiliar code, bugs, behavior,
  architecture, tools, docs, or external topics and returns evidence-based
  findings. Use when the user asks to research, investigate, understand, trace,
  explain why something works, compare options, or find root causes without
  making changes.
argument-hint: "<topic>"
---

# Investigate

Investigate a topic and return a structured, evidence-based report.

## Arguments

```
$ARGUMENTS
```

Required: a topic or question to investigate.

If no topic provided, stop and say: "Usage: /investigate <topic>"

## Method

Take the user-provided topic from the Arguments block as the topic. Review
conversation context for what is already known, and avoid re-investigating
settled questions.

Interpret the topic by identifying the core question, the scope implied by the
user, and any known constraints. If the topic is too broad, narrow to the most
relevant aspects and note what was excluded.

Identify distinct lines of inquiry: separate logical areas where different
evidence may answer different parts of the topic. When multiple lines of inquiry
are relevant, keep them distinct during investigation but merge their results
during synthesis. Avoid mixing unrelated evidence, and keep dependent questions
together when one answer informs another.

This investigation is read-only. Do not modify files, create objectives, or
update existing ones.

### Investigate

For each line of inquiry:

- Start broad, then narrow as evidence clarifies the topic.
- Follow leads that stay within the requested scope.
- Trace motivations: why something exists and what problem it solves.
- Map connections: how evidence relates to surrounding context.
- Keep dependent questions together so prerequisite answers inform later
  questions.

Ground claims in concrete evidence. Every finding needs a concrete source:
`file:line`, URL, or specific doc reference. A claim without a concrete source
is not a finding; either locate evidence or classify it as a Lead, Question, or
Assumption.

### Synthesize

Merge the lines of inquiry into a single report. Synthesize related findings,
reconcile conflicts with evidence from each side, and filter out what is already
known from conversation context. Order findings so prerequisites appear before
things that depend on them.

**Evidence scrutiny**: before including each finding, check its sources:

- Finding has a concrete source (`file:line`, URL, specific doc reference) ->
  include as finding.
- Finding has no source or only vague attribution ("the code", "the docs", "the
  codebase") -> demote to a lead with a note about what evidence is missing.
- Finding cites a source but the reference is imprecise, such as a file path
  without line number -> include as finding but note the imprecise source.

The Summary should synthesize across all relevant lines of inquiry, not
concatenate notes.

### Follow-Up

After synthesis, review the draft report's Questions and Leads sections to
identify gaps.

1. **Classify gaps**: Determine whether each question or lead is investigable or
   terminal. An investigable gap has an available source or targeted search path
   that could resolve it. A terminal gap has no available tool or source likely
   to answer it.
2. **Define gap resolution**: For each investigable gap, define the specific
   question, relevant context, and evidence needed to resolve it.
3. **Resolve and re-synthesize**: Use new evidence to promote confirmed leads to
   findings, resolve questions, update assumptions, and revise the summary.
   Apply the same evidence scrutiny and dependency ordering as the initial
   synthesis.
4. **Converge**: Repeat gap classification while investigable gaps remain and
   new evidence changes the report. Stop when the topic is sufficiently
   answered, all remaining gaps are terminal, or further investigation produces
   no new information.

Terminal gaps remain in the Questions section of the final report. Do not remove
them.

### Re-Verify

Before returning, re-verify key claims:

1. Re-read the relevant code or docs for the most important findings.
2. Confirm that file paths and line numbers are accurate, not stale from earlier
   investigation.
3. If a claim cannot be re-verified, move it from Findings to Leads.

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

- **Summary**: Direct answer to the topic. Should stand alone as a useful
  answer. Be concrete and opinionated where evidence supports it.
- **Findings**: Facts discovered with source/evidence. Each finding should be
  independently useful.
  - Use bullet list items, not numbered items. Sub-items are allowed for
    supporting detail.
  - State what was found, not just where.
  - Every finding must have at least one source sub-bullet.
  - Use `src:` prefix for web URLs and documentation references.
  - Use `ref:` prefix for file paths and line numbers.
- **Leads**: Plausible directions or hypotheses that lack direct evidence. These
  are worth following up but unconfirmed.
  - State the hypothesis and what prompted it.
  - Include what would confirm or refute it.
  - Attribute with source sub-bullets when available.
- **Questions**: Things that remain unanswered after investigation.
  - Attribute with source sub-bullets when a specific source prompted the
    question.
- **Assumptions**: Beliefs formed during investigation that lack direct
  evidence.
  - `[ ]` for unvalidated assumptions.
  - `[~]` for accepted working assumptions investigated across multiple passes
    or confirmed by the user without direct validation.
  - State what the assumption is and why it seems reasonable.
  - Note what would validate or invalidate it.
  - Attribute with source sub-bullets when a specific source informed the
    assumption.
