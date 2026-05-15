---
name: exa-web-search
description:
  Search the web through Exa MCP. Use when the user asks for current
  information, external documentation, recent facts, web research, or online
  verification.
---

# Exa Web Search

Use the `exa_web_search_exa` MCP tool when repository files and local knowledge
are not enough to answer the user's request.

## Requirements

- The `exa` server must be available through `pi-mcp-adapter`.
- The repository-managed server uses Exa's keyless endpoint.

## When To Use

Use this skill when the user asks for:

- Current or recent information.
- External documentation, API references, changelogs, or release notes.
- Web research, source discovery, or online fact checking.
- Verification of claims that cannot be confirmed from local files.

Do not use web search for questions that can be answered reliably from the
repository, local files, or already-provided context.

## Tool Calls

Call the direct tool when it is available:

```text
exa_web_search_exa({
  "query": "search query",
  "numResults": 8
})
```

On the first session after configuration, direct-tool metadata may not be
cached. Use the MCP proxy for that initial call; connecting populates the cache
and hot-loads the direct tool:

```text
mcp({
  "tool": "exa_web_search_exa",
  "args": {
    "query": "search query",
    "numResults": 8
  }
})
```

Raise `numResults` only when the additional evidence is useful.

## Search Practice

- Build precise queries from product names, API names, versions, exact errors,
  dates, and other distinguishing terms.
- Prefer official docs, primary sources, release notes, and reputable project
  repositories.
- Summarize results in your own words and include source names or links when the
  output provides them.
- Treat search output as evidence to evaluate, not as authoritative by default.
- If the tool reports an authentication or rate-limit failure, report that exact
  blocker and stop.
