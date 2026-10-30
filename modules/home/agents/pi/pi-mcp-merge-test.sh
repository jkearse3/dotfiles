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
  and (.mcpServers.exa | has("headers") | not)
  and .mcpServers.exa.timeout == 60 and .mcpServers.linear != null' "$config" >/dev/null

# First adoption on the exact declared endpoint fills absent authentication,
# while preserving explicit custom authentication and unrelated headers.
jq '.mcpServers.exa.headers = {"Authorization":"custom-fixture"}' "$defaults" >"$config"
bash "$merge" "$config" "$defaults"
jq -e '.mcpServers.exa.headers.Authorization == "custom-fixture"
  and .mcpServers.exa.headers["x-api-key"] == "${EXA_API_KEY}"' "$config" >/dev/null
jq '.mcpServers.exa.url += "/" | del(.mcpServers.exa.headers)' "$defaults" >"$config"
bash "$merge" "$config" "$defaults"
jq -e '.mcpServers.exa | has("headers") | not' "$config" >/dev/null

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

# Authentication changes only replace leaves still owned by the old defaults.
jq '.mcpServers.exa.headers = {"x-api-key":"${ROTATED_EXA_KEY}","Authorization":"${EXA_AUTH}"}' \
	"$defaults" >"$work/auth.json"
cp "$defaults" "$config"
bash "$merge" "$config" "$work/auth.json" "$defaults"
jq -e '.mcpServers.exa.headers == {"x-api-key":"${ROTATED_EXA_KEY}","Authorization":"${EXA_AUTH}"}' "$config" >/dev/null

jq '.mcpServers.exa.headers = {"x-api-key":"custom-fixture","X-Personal":"fixture"}' \
	"$defaults" >"$config"
bash "$merge" "$config" "$work/auth.json" "$defaults"
jq -e '.mcpServers.exa.headers == {"x-api-key":"custom-fixture","X-Personal":"fixture","Authorization":"${EXA_AUTH}"}' "$config" >/dev/null
cp "$config" "$work/reconciled.json"
bash "$merge" "$config" "$work/auth.json" "$work/auth.json"
cmp "$config" "$work/reconciled.json"

# A customized endpoint never receives new or changed declared headers. Even
# matching old headers are uncertain ownership here and must remain untouched.
# Keep the MCP environment placeholder literal, never reading a real key.
# shellcheck disable=SC2016
for headers in '{}' '{"x-api-key":"${EXA_API_KEY}"}' '{"Authorization":"custom-fixture"}'; do
	jq --argjson headers "$headers" '.mcpServers.exa.url = "https://custom.example/mcp"
    | .mcpServers.exa.headers = $headers' "$defaults" >"$config"
	bash "$merge" "$config" "$work/auth.json" "$defaults"
	jq -e --argjson headers "$headers" '.mcpServers.exa.url == "https://custom.example/mcp"
    and .mcpServers.exa.headers == $headers' "$config" >/dev/null
	cp "$config" "$work/reconciled.json"
	bash "$merge" "$config" "$work/auth.json" "$work/auth.json"
	cmp "$config" "$work/reconciled.json"
done

# URL declaration changes resolve before header reconciliation, in either
# direction. A user endpoint survives adoption; a changed URL declaration wins.
jq '.mcpServers.exa.url = "https://new.example/mcp"' "$work/auth.json" >"$work/url.json"
cp "$defaults" "$config"
bash "$merge" "$config" "$work/url.json" "$defaults"
jq -e '.mcpServers.exa.url == "https://new.example/mcp"
  and .mcpServers.exa.headers["x-api-key"] == "${ROTATED_EXA_KEY}"' "$config" >/dev/null
jq '.mcpServers.exa.url = "https://custom.example/mcp"' "$config" >"$work/custom.json"
cp "$work/custom.json" "$config"
bash "$merge" "$config" "$defaults" "$work/url.json"
jq -e '.mcpServers.exa.url == "https://mcp.exa.ai/mcp"
  and .mcpServers.exa.headers["x-api-key"] == "${ROTATED_EXA_KEY}"' "$config" >/dev/null

# Returning to the declared URL can fill absent auth, but keeps explicit null
# and custom values. Unchanged defaults must still respect header deletions.
for headers in '{}' 'null' '{"x-api-key":"custom-fixture"}'; do
	jq --argjson headers "$headers" '.mcpServers.exa.url = "https://new.example/mcp"
    | .mcpServers.exa.headers = $headers' "$work/url.json" >"$config"
	bash "$merge" "$config" "$defaults" "$work/url.json"
	if [[ $headers == '{}' ]]; then
		jq -e '.mcpServers.exa.headers["x-api-key"] == "${EXA_API_KEY}"' "$config" >/dev/null
	else
		jq -e --argjson headers "$headers" '.mcpServers.exa.headers == $headers' "$config" >/dev/null
	fi
done
jq 'del(.mcpServers.exa.headers)' "$defaults" >"$config"
bash "$merge" "$config" "$defaults" "$defaults"
jq -e '.mcpServers.exa | has("headers") | not' "$config" >/dev/null

# Retiring headers removes defaults only at the declared URL, retaining custom
# leaves and all existing headers at custom endpoints.
jq 'del(.mcpServers.exa.headers)' "$defaults" >"$work/no-auth.json"
cp "$defaults" "$config"
bash "$merge" "$config" "$work/no-auth.json" "$defaults"
jq -e '.mcpServers.exa | has("headers") | not' "$config" >/dev/null
jq '.mcpServers.exa.headers.Authorization = "custom-fixture"' "$defaults" >"$config"
bash "$merge" "$config" "$work/no-auth.json" "$defaults"
jq -e '.mcpServers.exa.headers == {"Authorization":"custom-fixture"}' "$config" >/dev/null
jq '.mcpServers.exa.url = "https://custom.example/mcp"' "$defaults" >"$config"
bash "$merge" "$config" "$work/no-auth.json" "$defaults"
jq -e '.mcpServers.exa.headers["x-api-key"] == "${EXA_API_KEY}"' "$config" >/dev/null
bash "$merge" "$config" "$work/empty.json" "$work/no-auth.json"
jq -e '.mcpServers.exa.headers["x-api-key"] == "${EXA_API_KEY}"' "$config" >/dev/null

# Invalid old/new JSON (including valid JSON of the wrong type) never clobbers.
for invalid in '{broken' '[]' 'null'; do
	printf '%s\n' "$invalid" >"$work/invalid.json"
	cp "$defaults" "$config"
	mode=$(stat -c %a "$config")
	for source in old new; do
		old=$defaults
		new=$defaults
		if [[ $source == old ]]; then old=$work/invalid.json; else new=$work/invalid.json; fi
		if bash "$merge" "$config" "$new" "$old" 2>/dev/null; then
			echo "invalid $source unexpectedly accepted" >&2
			exit 1
		fi
		cmp "$config" "$defaults"
		test "$(stat -c %a "$config")" = "$mode"
	done
done

# Invalid live JSON never destroys the original file.
for invalid in '{broken' '[]' 'null'; do
	printf '%s\n' "$invalid" >"$config"
	cp "$config" "$work/broken.json"
	if bash "$merge" "$config" "$defaults" 2>/dev/null; then
		echo 'invalid config unexpectedly accepted' >&2
		exit 1
	fi
	cmp "$config" "$work/broken.json"
done
echo 'pi MCP merge tests passed'
