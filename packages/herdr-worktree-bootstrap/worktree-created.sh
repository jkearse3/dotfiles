#!/usr/bin/env bash

set -euo pipefail

notify_bootstrap_failure() {
	exit_code=$?
	trap - ERR
	notification_body="Check Herdr plugin logs for details."
	if [[ ${checkout_path_resolved:-false} == true ]]; then
		notification_body="Checkout: $checkout_path"$'\n\n'"$notification_body"
	fi

	if [[ -n ${HERDR_BIN_PATH:-} ]]; then
		"$HERDR_BIN_PATH" notification show "Worktree bootstrap failed" \
			--body "$notification_body" \
			--sound request >/dev/null 2>&1 || true
	fi

	exit "$exit_code"
}

trap notify_bootstrap_failure ERR
checkout_path_resolved=false

if [[ -n ${HERDR_PLUGIN_EVENT_JSON:-} ]]; then
	checkout_path=$(
		printf '%s' "$HERDR_PLUGIN_EVENT_JSON" |
			jq -er '.data.worktree.path'
	)
else
	checkout_path=$(
		printf '%s' "${HERDR_PLUGIN_CONTEXT_JSON:?}" |
			jq -er '.worktree | select(.is_linked_worktree == true) | .checkout_path'
	)
fi
checkout_path_resolved=true

cd "$checkout_path"

# Herdr runs bootstrap events asynchronously; the action retries every setup step.
jj-ensure "$checkout_path"
