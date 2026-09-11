---
name: interrogate
description: >-
  Interviews the user to resolve material decisions in a plan, decision, or
  idea. Use when shared understanding depends on unresolved intent, ownership,
  priorities, risk tolerance, or tradeoffs, or when the user asks to
  interrogate, validate, refine, de-risk, clarify, stress-test, or challenge
  their thinking. Not for factual investigation, implementation planning, or
  routine implementation choices.
---

# Interrogate

Establish a precise shared understanding of the subject through a decision
interview. Do not plan or act on the subject.

1. Identify the subject, intended outcome, and necessary scope from the request
   and context. Ask only if the subject is absent or materially ambiguous.
2. Model unresolved material decisions and their dependencies. A decision is
   material when a different answer could change the outcome, behavior, scope,
   ownership, compatibility, risk, validation, or a costly direction.
3. Classify each unknown before asking:
   - Establish discoverable facts through safe read-only inspection.
   - Ask the user for decisions that depend on their intent, priorities,
     ownership, or accepted tradeoffs; never decide these for them.
   - Defer implementation unknowns only when they can be resolved safely within
     the agreed boundaries without changing the material direction.
   - State non-material assumptions only when they affect interpretation, with
     what would invalidate them.
4. Resolve parent decisions before dependents and reassess after every answer.
   Ask exactly one question per turn, state the decision and relevant context,
   recommend an answer with rationale, explain material tradeoffs, and wait.
5. Pressure-test the emerging understanding for unsupported assumptions, hidden
   scope, speculative requirements, weak boundaries, overlooked failure modes,
   and validation that would not prove the intended outcome. Ask further only
   when this reveals a material decision.
6. Stop when all material decisions are resolved and remaining unknowns are safe
   to defer.

Summarize only material decisions and rationale, boundaries, assumptions and
invalidators, and implementation unknowns. Ask the user to confirm the summary;
incorporate corrections from the earliest affected decision.

Do not use a fixed taxonomy or manufacture questions for exhaustiveness. Never
infer user-owned decisions from defaults, prior behavior, or implementation
convenience. Treat a vague deferral as unresolved when it could change the
agreed direction; explain what it blocks and stop if the user declines to
decide.

User confirmation ends the interview but does not authorize implementation,
persistent changes, external actions, or version-control mutations.
