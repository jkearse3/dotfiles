---
name: investigate
description: >-
  Investigates questions across code, systems, documents, products, history, and
  other domains using read-only evidence. Use for research, root-cause
  diagnosis, behavior tracing, factual comparisons, or explanations; not for
  routine implementation inspection, brainstorming, or open-ended ideation.
argument-hint: "<question or topic>"
---

# Investigate

Investigate the requested question without making persistent changes.

## Input

```text
$ARGUMENTS
```

Use the arguments and relevant conversation context to identify the controlling
question. If no question or topic can be established, ask for one and stop.

## Method

1. Establish the controlling question, relevant scope, and any exclusions that
   materially affect the answer. Identify the evidence most likely to decide the
   question.
2. Divide the question into the smallest useful lines of inquiry. Keep dependent
   questions together so earlier findings can direct later research; keep
   independent lines distinct until synthesis.
3. Investigate each line using relevant artifacts, documentation, history,
   observed behavior, or external sources. Resolve available factual questions
   directly rather than asking the user.
4. When independent lines can be researched concurrently, use the execution
   environment's available concurrency mechanisms. Otherwise, investigate them
   sequentially in priority order. Concurrency is optional and its absence must
   not block or weaken the investigation.
5. Synthesize results across all lines into a provisional answer. Reconcile
   conflicting evidence, distinguish observed facts from inferences, and
   identify gaps that could change the conclusion.
6. Pursue bounded follow-up research for material gaps with an available source
   or targeted search path, concurrently when useful and supported.
   Re-synthesize after incorporating new evidence.
7. Stop when the controlling question is sufficiently answered, remaining
   uncertainty would not change the conclusion or next action, or no productive
   evidence path remains.
8. Re-check the decisive evidence before concluding.

The invoking investigator remains responsible for scope, synthesis, conflict
resolution, evidence quality, and the final conclusion regardless of how
individual lines of inquiry are executed.

## Result

Lead with a direct answer, followed by the material findings and precise sources
that support it. Identify inferences as such. Retain unresolved uncertainty only
when it could change the conclusion or next action, and state what would resolve
it.

Synthesize the evidence rather than returning raw notes or a chronological
research transcript. Do not turn findings into an implementation plan or perform
the described work unless the user separately requests it.
