#!/usr/bin/env bash
# Opens one of this plugin's popup panes. Keys can bind only plugin actions,
# and an action runs without a terminal, so each action opens its popup.

set -euo pipefail

exec "${HERDR_BIN_PATH:-herdr}" plugin pane open --plugin "${HERDR_PLUGIN_ID:?}" --entrypoint "${1:?}" --focus >/dev/null
