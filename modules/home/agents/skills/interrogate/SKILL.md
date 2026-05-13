---
name: interrogate
description: Interview the user relentlessly about a plan, design, or idea until no uncertainties remain, resolving each branch of the decision tree.
argument-hint: "<topic>"
---

# Interrogate

## Arguments

```
$ARGUMENTS
```

If `$ARGUMENTS` is non-empty, treat it as the topic to interrogate.

If `$ARGUMENTS` is empty, derive the topic from conversation history — look at what the user just
said or what they're working on.

When a topic is obtained (from args or context), open the interrogation by stating: "Interrogating:
<topic>"

When no topic can be derived — neither from args nor from conversation context — prompt the user:
"What would you like to interrogate?" If the user still provides no topic, stop with an error.

## Execution

Interview me relentlessly about every aspect of this until no uncertainties remain. Walk down each
branch of the decision tree, resolving dependencies between decisions one-by-one. For each question,
provide your recommended answer. Ask questions one at a time.

If a question can be answered by research (codebase exploration, web search, etc.), do the research
instead of asking.

Systematically probe every dimension of the plan. Question assumptions, challenge trade-offs, poke
at edge cases, trace dependencies, flag risks, demand a validation strategy, and check that the
scope boundaries are right.

As each branch resolves, record the decision in a running log:

```
### Decisions

- [x] use postgres over mysql; the team knows it and sharding isn't needed
- [ ] decide on migration strategy
```

Stop when every branch is resolved and no open questions remain.
