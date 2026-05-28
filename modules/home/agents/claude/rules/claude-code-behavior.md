# Claude Code Behavior

Rules for Claude Code behavior.

## User Questions

When you need to ask the user a question, use the `AskUserQuestion` tool. Do not ask the question
inline in assistant text unless the tool is unavailable or the question is rhetorical and does not
require a user response.
