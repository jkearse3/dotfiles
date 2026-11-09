#!/usr/bin/env bash
# Fixtures for `keys-check.jq`, run as a build gate by the derivation in
# `keys-json.nix`. Takes the jq program under test as its only argument and
# runs it with the `jq` on PATH. Each fixture feeds the program small keys
# sections and prefix bindings and hints against fixed command and mod
# names, and compares everything it prints with the expected problem lines.
set -euo pipefail
export LC_ALL=C

check=${1:?usage: keys-check-test.sh <keys-check.jq>}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

printf '%s\n' '["app.help","tab.new","tab.select","mod.open"]' >"$work/commands.json"
printf '%s\n' '["prefix","alpha"]' >"$work/mods.json"

fail() {
	echo "FAIL: $1" >&2
	exit 1
}

# Runs the check on KEYS (the merged keys.json, OVERRIDES unless given) with
# OVERRIDES as the `keys.nix` sections and PREFIX as its `prefix` (bindings
# and hints), all JSON, and fails fixture NAME unless it prints exactly the EXPECTED lines
# (empty for none).
expect_problems() {
	local name=$1 overrides=$2 prefix=$3 expected=$4 keys=${5:-$2}
	local actual

	printf '%s\n' "$overrides" >"$work/overrides.json"
	printf '%s\n' "$prefix" >"$work/prefix.json"
	printf '%s\n' "$keys" >"$work/keys.json"

	if ! jq -r \
		--slurpfile commands "$work/commands.json" \
		--slurpfile mods "$work/mods.json" \
		--slurpfile overrides "$work/overrides.json" \
		--slurpfile prefix "$work/prefix.json" \
		-f "$check" "$work/keys.json" >"$work/problems.txt"; then
		fail "$name: jq exited nonzero"
	fi

	actual=$(<"$work/problems.txt")
	if [[ $actual != "$expected" ]]; then
		printf 'expected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
		fail "$name: problems differ"
	fi
}

# Unless a fixture tests rule 6, its `global` and `mod:prefix` bind `ctrl-b`
# as required, so the check prints only the problem under test.
global='"global": {"ctrl-b": "mod.open:prefix"}'
mod_prefix='"mod:prefix": {"ctrl-b": "prefix.ctrl-b"}'
prefix='{"bindings": {"ctrl-b": "send:\u0002", "c": "tab.new"}, "hints": []}'

expect_problems "valid bindings" \
	'{
		"global": {"ctrl-b": "mod.open:prefix", "cmd-1": "tab.select:3", "cmd-o": "mod.open:alpha"},
		"terminal": {"ctrl-x": "terminal", "ctrl-y": "send:x", "h": "alpha.cmd"},
		'"$mod_prefix"'
	}' \
	'{
		"bindings": {"ctrl-b": "send:\u0002", "h": "app.help", "c": "tab.new", "o": "mod.open:alpha", "1": "tab.select:1"},
		"hints": [{"action": "mod.open:alpha", "label": "alpha"}, {"action": "tab.select", "label": "tab"}]
	}' \
	'' \
	'{
		"global": {"ctrl-b": "mod.open:prefix", "cmd-1": "tab.select:3", "cmd-o": "mod.open:alpha", "cmd-z": "nonsense"},
		"terminal": {"ctrl-x": "terminal", "ctrl-y": "send:x", "h": "alpha.cmd"},
		'"$mod_prefix"'
	}'

expect_problems "unknown action" \
	'{'"$global"', '"$mod_prefix"', "terminal": {"cmd-u": "nonsense"}}' \
	"$prefix" \
	'terminal.cmd-u: unknown action "nonsense"'

expect_problems "mod command for an unknown mod" \
	'{'"$global"', '"$mod_prefix"', "terminal": {"cmd-u": "beta.cmd"}}' \
	"$prefix" \
	'terminal.cmd-u: unknown action "beta.cmd"'

expect_problems "mod command with no command" \
	'{'"$global"', '"$mod_prefix"', "terminal": {"cmd-u": "alpha."}}' \
	"$prefix" \
	'terminal.cmd-u: unknown action "alpha."'

expect_problems "mod.open of an unknown mod" \
	'{'"$global"', '"$mod_prefix"', "terminal": {"cmd-u": "mod.open:beta"}}' \
	"$prefix" \
	'terminal.cmd-u: unknown mod in "mod.open:beta"'

expect_problems "section not an object" \
	'{'"$global"', '"$mod_prefix"'}' \
	"$prefix" \
	'terminal: not an object of bindings' \
	'{'"$global"', '"$mod_prefix"', "terminal": "tab.new"}'

expect_problems "action not a string" \
	'{'"$global"', '"$mod_prefix"'}' \
	"$prefix" \
	'terminal.cmd-u: action is not a string' \
	'{'"$global"', '"$mod_prefix"', "terminal": {"cmd-u": 1}}'

expect_problems "wrong ctrl-b in mod:prefix" \
	'{'"$global"', "mod:prefix": {"ctrl-b": "app.help"}}' \
	"$prefix" \
	'mod:prefix.ctrl-b: ctrl-b in prefix mode must go to the prefix mod (prefix.ctrl-b)
mod:prefix: ctrl-b is not bound to prefix.ctrl-b'

expect_problems "wrong ctrl-b in global" \
	'{"global": {"ctrl-b": "app.help"}, '"$mod_prefix"'}' \
	"$prefix" \
	'global.ctrl-b: ctrl-b alone must open prefix mode (mod.open:prefix)
global: ctrl-b is not bound to mod.open:prefix'

expect_problems "ctrl-b alone in another section" \
	'{'"$global"', '"$mod_prefix"', "terminal": {"ctrl-b": "terminal"}}' \
	"$prefix" \
	'terminal.ctrl-b: ctrl-b alone must open prefix mode (mod.open:prefix)'

expect_problems "chord starting with ctrl-b" \
	'{'"$global"', '"$mod_prefix"', "terminal": {"ctrl-b c": "tab.new"}}' \
	"$prefix" \
	'terminal.ctrl-b c: a chord starting with ctrl-b can never fire, because prefix mode takes ctrl-b; add the key to the prefix bindings in keys.nix instead'

expect_problems "global without ctrl-b" \
	'{"global": {"cmd-1": "tab.new"}, '"$mod_prefix"'}' \
	"$prefix" \
	'global: ctrl-b is not bound to mod.open:prefix'

expect_problems "mod:prefix without ctrl-b" \
	'{'"$global"'}' \
	"$prefix" \
	'mod:prefix: ctrl-b is not bound to prefix.ctrl-b'

expect_problems "prefix keystroke bound in global" \
	'{"global": {"ctrl-b": "mod.open:prefix", "c": "app.help"}, '"$mod_prefix"'}' \
	"$prefix" \
	'prefix.c: global also binds c, and that app binding takes the key before prefix mode sees it'

expect_problems "prefix keystroke bound in a layout section" \
	'{'"$global"', '"$mod_prefix"', "layout:x": {"c": "app.help"}}' \
	"$prefix" \
	'prefix.c: layout:x also binds c, and that app binding takes the key before prefix mode sees it'

expect_problems "prefix binding of a chord" \
	'{'"$global"', '"$mod_prefix"'}' \
	'{"bindings": {"ctrl-b": "send:\u0002", "g g": "tab.new"}, "hints": []}' \
	'prefix.g g: not a single keystroke'

expect_problems "prefix action not a string" \
	'{'"$global"', '"$mod_prefix"'}' \
	'{"bindings": {"ctrl-b": "send:\u0002", "c": 1}, "hints": []}' \
	'prefix.c: action is not a string'

expect_problems "terminal as a prefix action" \
	'{'"$global"', '"$mod_prefix"'}' \
	'{"bindings": {"ctrl-b": "send:\u0002", "c": "terminal"}, "hints": []}' \
	'prefix.c: terminal is not a prefix action'

expect_problems "prefix send of two characters" \
	'{'"$global"', '"$mod_prefix"'}' \
	'{"bindings": {"ctrl-b": "send:\u0002", "c": "send:ab"}, "hints": []}' \
	'prefix.c: send: text must be one control character U+0001-U+001A'

expect_problems "prefix send of a control character past ctrl-z" \
	'{'"$global"', '"$mod_prefix"'}' \
	'{"bindings": {"ctrl-b": "send:\u0002", "c": "send:\u001b"}, "hints": []}' \
	'prefix.c: send: text must be one control character U+0001-U+001A'

expect_problems "unknown prefix action" \
	'{'"$global"', '"$mod_prefix"'}' \
	'{"bindings": {"ctrl-b": "send:\u0002", "c": "nonsense"}, "hints": []}' \
	'prefix.c: unknown action "nonsense"'

expect_problems "prefix hint no binding uses" \
	'{'"$global"', '"$mod_prefix"'}' \
	'{"bindings": {"ctrl-b": "send:\u0002", "c": "tab.new"}, "hints": [{"action": "tab.new", "label": "new tab"}, {"action": "app.help", "label": "help"}]}' \
	'prefix.hints[1]: no prefix binding uses "app.help"'

expect_problems "prefix hint not an object with string action and label" \
	'{'"$global"', '"$mod_prefix"'}' \
	'{"bindings": {"ctrl-b": "send:\u0002", "c": "tab.new"}, "hints": ["tab.new", {"action": "tab.new"}]}' \
	'prefix.hints[0]: not an object with string action and label
prefix.hints[1]: not an object with string action and label'
