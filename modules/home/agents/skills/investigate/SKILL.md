---
name: investigate
description: >-
  Answers standalone questions whose requested result is an evidence-backed
  factual conclusion, including research, root-cause diagnosis, behavior
  tracing, factual comparison, and explanation. Use when inspection is needed
  and no more specific skill owns the result; not for implementation, planning,
  diff review or summary, user-decision interrogation, brainstorming, or a
  single known fact at a known location.
argument-hint: "<question or topic>"
---

# Investigate

Answer the controlling question using safe read-only evidence. Investigation
does not grant authority to implement its findings.

## Input

```text
$ARGUMENTS
```

Use the arguments and relevant conversation context to identify the controlling
question. Ask only when no question is available or materially different
interpretations would change the scope or conclusion.

## Method

1. Frame the controlling question, material scope and exclusions, and the
   evidence most likely to decide it. Split lines of inquiry only when they need
   distinct evidence or dependency order.
2. Gather the cheapest authoritative evidence that settles each line. Use only
   inspections and diagnostics that leave no persistent repository or external
   state and do not notify, incur cost, or acquire resources without authority.
   Keep dependent paths ordered; parallelize independent paths when useful.
3. Synthesize the evidence, reconcile conflicts, distinguish observations from
   inferences, and pursue bounded follow-up for gaps that could change the
   conclusion or next action. Stop when no productive material evidence path
   remains.
4. Re-check the decisive claims and source locations before reporting.

## Result

Lead with the direct answer, followed by material findings and precise sources.
Identify inferences and report only uncertainty, exclusions, or evidence limits
that affect the conclusion or next action.

Synthesize the evidence rather than returning raw notes or a chronological
research transcript. Do not turn findings into a plan or execute recommendations
as part of the investigation.
