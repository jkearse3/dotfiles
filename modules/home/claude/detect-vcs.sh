#!/usr/bin/env bash
set -euo pipefail

# Detect VCS type for the current working directory.
# Called by Claude's UserPromptSubmit hook; outputs additionalContext JSON.
# Silent (no output) when no VCS is detected.

if jj root --ignore-working-copy &>/dev/null; then
	vcs="jj"
elif git rev-parse --git-dir &>/dev/null; then
	vcs="git"
else
	vcs="none. Avoid VCS commands unless initializing — use jj git init --colocate."
fi

jq -n --arg ctx "VCS: ${vcs}" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
