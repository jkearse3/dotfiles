#!/usr/bin/env bash

# Reconcile Nix MCP defaults into Pi's writable config. Unchanged declarations
# leave live values (including deletions) alone; changed declarations win except
# for customized Exa headers. Exa header defaults belong only to the declared URL.
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
# Headers have a stricter ownership rule than other defaults: changes must not
# overwrite custom leaves, even when the declaration changes. A URL transition
# can adopt absent headers, but cannot establish ownership of existing ones.
def reconcile_headers($live; $old; $new; $adopt; $managed):
  reduce (($old + $new) | keys_unsorted[]) as $key ($live;
    if ($new | has($key) | not) then
      if $managed and has($key) and .[$key] == $old[$key] then del(.[$key]) else . end
    elif ($new[$key] | type) == "object"
      and (($old[$key] // {}) | type) == "object"
      and ((has($key) | not) or (.[$key] | type) == "object") then
      .[$key] = reconcile_headers(.[$key] // {}; $old[$key] // {}; $new[$key]; $adopt; $managed)
    elif has($key) then
      if $managed and ($old | has($key)) and .[$key] == $old[$key]
      then .[$key] = $new[$key] else . end
    elif $adopt or ($old | has($key) | not) or $old[$key] != $new[$key]
    then .[$key] = $new[$key]
    else . end);
def reconcile($live; $old; $new; $path):
  reduce (($old + $new) | keys_unsorted[]) as $key ($live;
    if $path == ["mcpServers", "exa"] and $key == "headers" then
      (reconcile($live | del(.headers); $old | del(.headers); $new | del(.headers); [])) as $server
      | if ($new.url | type) != "string" or $server.url != $new.url then .
        elif (has("headers") and (.headers | type) != "object")
          or (($old.headers // {}) | type) != "object"
          or (($new.headers // {}) | type) != "object" then .
        else
          reconcile_headers(.headers // {}; $old.headers // {}; $new.headers // {};
            $live.url != $server.url or $old.url != $new.url;
            $live.url == $old.url) as $headers
          | if ($new | has("headers") | not) and $headers == {} then del(.headers)
            elif has("headers") or ($headers | length) > 0 then .headers = $headers else . end
        end
    elif ($new | has($key) | not) then
      if has($key) and .[$key] == $old[$key] then del(.[$key]) else . end
    elif ($old | has($key)) and $old[$key] == $new[$key] then .
    elif ($new[$key] | type) == "object"
      and (($old[$key] // {}) | type) == "object"
      and ((.[$key] // {}) | type) == "object" then
      .[$key] = reconcile(.[$key] // {}; $old[$key] // {}; $new[$key]; $path + [$key])
    elif ($old | has($key)) then .[$key] = $new[$key]
    elif has($key) then .
    else .[$key] = $new[$key]
    end);
if ($live | type) != "object" or ($old | type) != "object"
  or ($declared[0] | type) != "object" then error("MCP config must be an object")
else reconcile($live; $old; $declared[0]; []) end
' >"$tmp"
mv -- "$tmp" "$config"
trap - EXIT
