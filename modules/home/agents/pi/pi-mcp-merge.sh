#!/usr/bin/env bash

# Reconcile Nix MCP defaults into Pi's writable config. Unchanged declarations
# leave live values (including deletions) alone; changed declarations win.
# Retired values are removed only if the user has not customized them.
# usage: pi-mcp-merge <config> <declared-json> [<previous-declared-json>]
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
	echo 'usage: pi-mcp-merge <config> <declared-json> [<previous-declared-json>]' >&2
	exit 2
fi

config=$1
declared=$2
previous=${3-}
mkdir -p -- "$(dirname -- "$config")"
live='{}'
[[ ! -f $config ]] || live=$(cat -- "$config")
old='{}'
[[ -z $previous || ! -f $previous ]] || old=$(cat -- "$previous")

# Write beside the destination so replacement is atomic and remains mode 0600.
tmp=$(mktemp "${config}.XXXXXX")
trap 'rm -f -- "$tmp"' EXIT
# shellcheck disable=SC2016
jq -n --argjson live "$live" --argjson old "$old" --slurpfile declared "$declared" '
def reconcile($live; $old; $new):
  reduce (($old + $new) | keys_unsorted[]) as $key ($live;
    if ($new | has($key) | not) then
      if has($key) and .[$key] == $old[$key] then del(.[$key]) else . end
    elif ($old | has($key)) and $old[$key] == $new[$key] then .
    elif ($new[$key] | type) == "object"
      and (($old[$key] // {}) | type) == "object"
      and ((.[$key] // {}) | type) == "object" then
      .[$key] = reconcile(.[$key] // {}; $old[$key] // {}; $new[$key])
    elif ($old | has($key)) then .[$key] = $new[$key]
    elif has($key) then .
    else .[$key] = $new[$key]
    end);
if ($live | type) != "object" or ($old | type) != "object"
  or ($declared[0] | type) != "object" then error("MCP config must be an object")
else reconcile($live; $old; $declared[0]) end
' >"$tmp"
mv -- "$tmp" "$config"
trap - EXIT
