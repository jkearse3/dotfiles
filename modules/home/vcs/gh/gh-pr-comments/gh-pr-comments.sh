#!/usr/bin/env bash

# Fetch unresolved PR review comments as JSON.
# Usage: gh-pr-comments [pr-number]
# When pr-number is omitted, auto-detects from current branch.

set -euo pipefail

pr_num="${1:-}"

# Get repo owner and name.
repo_info=$(gh repo view --json owner,name --jq '.owner.login + "/" + .name')
owner="${repo_info%/*}"
repo="${repo_info#*/}"

# Auto-detect PR number from current branch if not provided.
if [[ -z $pr_num ]]; then
	branch=$(jj-bookmark-current)
	if [[ -z $branch ]]; then
		echo "error: no branch found for current revision" >&2
		exit 1
	fi
	pr_num=$(gh pr view "$branch" --json number --jq '.number')
fi

pr_url="https://github.com/${owner}/${repo}/pull/${pr_num}"

query=$(
	cat <<'GRAPHQL'
{
  repository(owner: "%s", name: "%s") {
    pullRequest(number: %d) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          comments(first: 1) {
            nodes { databaseId id body path line diffHunk author { login } createdAt url }
          }
        }
      }
    }
  }
}
GRAPHQL
)

# shellcheck disable=SC2059
query=$(printf "$query" "$owner" "$repo" "$pr_num")

# Flatten GraphQL response, filter resolved, inject prNumber/prUrl.
export PR_NUM="$pr_num"
export PR_URL="$pr_url"

# shellcheck disable=SC2016 # $ENV is a jq variable, not a shell variable.
jq_expr='[.data.repository.pullRequest.reviewThreads.nodes[]
  | {threadId: .id, isResolved, isOutdated, c: .comments.nodes[0]}
  | {databaseId: .c.databaseId, commentId: .c.id, threadId, body: .c.body,
     path: .c.path, line: .c.line, diffHunk: .c.diffHunk,
     author: .c.author.login, createdAt: .c.createdAt, url: .c.url,
     isResolved, isOutdated}
  | select(.isResolved | not)
  | . + {prNumber: ($ENV.PR_NUM | tonumber), prUrl: $ENV.PR_URL}]'

gh api graphql -f "query=${query}" --jq "$jq_expr"
