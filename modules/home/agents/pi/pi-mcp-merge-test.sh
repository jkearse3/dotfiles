#!/usr/bin/env bash
set -euo pipefail
merge=$1
defaults=$2
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
config="$work/mcp.json"

bash "$merge" "$config" "$defaults" "$work/missing.json"
cmp "$config" <(jq . "$defaults")
test "$(stat -c %a "$config")" = 600

jq '.mcpServers.exa.enabled = false | .mcpServers.linear.exposure = "deferred"
  | .mcpServers.personal = {"url":"https://example.com/mcp"}
  | .autoEnableCodemode = false' "$config" >"$work/custom.json"
cp "$work/custom.json" "$config"
bash "$merge" "$config" "$defaults" "$defaults"
cmp "$config" "$work/custom.json"

jq '.mcpServers.exa.timeout = 90' "$defaults" >"$work/changed.json"
bash "$merge" "$config" "$work/changed.json" "$defaults"
jq -e '.mcpServers.exa.timeout == 90 and .mcpServers.exa.enabled == false
  and .mcpServers.linear.exposure == "deferred" and .mcpServers.personal != null
  and .autoEnableCodemode == false' "$config" >/dev/null

# First adoption preserves an existing server while filling absent defaults.
printf '%s\n' '{"mcpServers":{"exa":{"url":"https://custom.example/mcp"}}}' >"$config"
bash "$merge" "$config" "$defaults"
jq -e '.mcpServers.exa.url == "https://custom.example/mcp"
  and .mcpServers.exa.timeout == 60 and .mcpServers.linear != null' "$config" >/dev/null

# Unchanged declarations do not resurrect servers removed through pi mcp remove.
printf '%s\n' '{"mcpServers":{}}' >"$config"
bash "$merge" "$config" "$defaults" "$defaults"
jq -e '.mcpServers == {}' "$config" >/dev/null

# Retirement removes untouched servers but keeps customized ones.
cp "$defaults" "$config"
jq '.mcpServers.linear.enabled = false' "$config" >"$work/custom.json"
cp "$work/custom.json" "$config"
printf '%s\n' '{"mcpServers":{}}' >"$work/empty.json"
bash "$merge" "$config" "$work/empty.json" "$defaults"
jq -e '.mcpServers.exa == null and .mcpServers.linear.enabled == false' "$config" >/dev/null

# Invalid live JSON never destroys the original file.
printf '%s\n' '{broken' >"$config"
cp "$config" "$work/broken.json"
if bash "$merge" "$config" "$defaults" 2>/dev/null; then
	echo 'invalid config unexpectedly accepted' >&2
	exit 1
fi
cmp "$config" "$work/broken.json"
echo 'pi MCP merge tests passed'
