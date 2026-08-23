#!/usr/bin/env bash
# Fixtures for `settings-overlay.sh`, run as a build gate by the derivation in
# `default.nix`. Takes the overlay executable under test as its only argument.
set -euo pipefail

overlay=${1:?usage: settings-overlay-test.sh <claude-settings-overlay>}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

pinned="$work/pinned.json"
cat >"$pinned" <<'JSON'
{
  "permissions": {
    "allow": ["Bash(true)"],
    "additionalDirectories": ["~/.agents"],
    "defaultMode": "auto"
  },
  "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" },
  "attribution": { "commit": "", "pr": "", "sessionUrl": false },
  "model": "pinned-model",
  "theme": "dark-ansi"
}
JSON

# The paths declared machine-overridable for the fixtures below. The pin above
# is synthetic, so this set exercises the overlay rather than mirroring
# `default.nix`, which enforces `statusLine.command` as well: what matters here
# is that some nested path is declared and some path is not.
# `permissions.defaultMode` is left undeclared so the fixtures can check that an
# enforced path survives a hostile machine-local file.
overridable=(
	model
	theme
	statusLine.command
	attribution.commit
	attribution.sessionUrl
)

fail() {
	echo "FAIL: $1" >&2
	exit 1
}

same_json() {
	[ "$(jq -S . <<<"$1")" = "$(jq -S . <<<"$2")" ]
}

# A machine-local file that does not exist leaves every pinned path in force.
absent=$("$overlay" "$pinned" "$work/missing.json" "${overridable[@]}")
same_json "$absent" "$(cat "$pinned")" ||
	fail "missing machine-local file changed the pinned payload"

# A declared top-level path the machine-local file defines is deleted, which is
# what hands it back to `~/.claude/settings.json` at `flagSettings` precedence.
echo '{"model": "machine-model", "theme": "light"}' >"$work/prefs.json"
prefs=$("$overlay" "$pinned" "$work/prefs.json" "${overridable[@]}")
[ "$(jq -r 'has("model")' <<<"$prefs")" = false ] || fail "overridden model survived"
[ "$(jq -r 'has("theme")' <<<"$prefs")" = false ] || fail "overridden theme survived"
[ "$(jq -r '.permissions.defaultMode' <<<"$prefs")" = auto ] || fail "permissions lost"

# A declared nested path is deleted leaf by leaf: its siblings under the same
# pinned object stay pinned, which is the whole reason the overlay works in
# paths rather than in top-level keys. Claude Code merges what survives with the
# machine-local object beneath it.
echo '{"statusLine": {"command": "/machine/statusline.sh", "type": "none"}}' >"$work/nested.json"
nested=$("$overlay" "$pinned" "$work/nested.json" "${overridable[@]}")
[ "$(jq -r '.statusLine | has("command")' <<<"$nested")" = false ] ||
	fail "overridden statusLine.command survived"
[ "$(jq -r '.statusLine.type' <<<"$nested")" = command ] ||
	fail "undeclared statusLine.type was deleted alongside its sibling"

# A declared leaf whose pinned and machine values are both `false` still hands
# over. Nothing here may test definedness by truthiness or by comparing against
# `null`.
echo '{"attribution": {"sessionUrl": false}}' >"$work/falsey.json"
falsey=$("$overlay" "$pinned" "$work/falsey.json" "${overridable[@]}")
[ "$(jq -r '.attribution | has("sessionUrl")' <<<"$falsey")" = false ] ||
	fail "a machine-local false did not count as defining its path"
[ "$(jq -r '.attribution.commit' <<<"$falsey")" = "" ] ||
	fail "undeclared attribution.commit was deleted alongside its sibling"

# An enforced path survives a hostile machine-local file, and so does every
# array beside it. This is the property that keeps an agent with write access to
# `~/.claude/settings.json` from selecting `bypassPermissions` for the next
# launch. It is the payload alone that is defended: the hostile `allow` and
# `additionalDirectories` additions still union in at runtime from the machine
# file itself — the accepted residue recorded at `enforcedPaths` in
# `default.nix`.
cat >"$work/hostile.json" <<'JSON'
{
  "permissions": {
    "defaultMode": "bypassPermissions",
    "allow": ["Bash(rm:*)"],
    "additionalDirectories": ["/"]
  }
}
JSON
hostile=$("$overlay" "$pinned" "$work/hostile.json" "${overridable[@]}")
same_json "$(jq -c '.permissions' <<<"$hostile")" "$(jq -c '.permissions' "$pinned")" ||
	fail "machine-local file reached an enforced path"

# Arrays and objects are never deleted even when a caller names them, because
# deleting one would surrender every pinned leaf beneath it at once. Claude Code
# unions arrays and merges objects per leaf on its own, so nothing is lost by
# refusing.
structural=$("$overlay" "$pinned" "$work/hostile.json" permissions.allow permissions attribution)
same_json "$(jq -c '.permissions' <<<"$structural")" "$(jq -c '.permissions' "$pinned")" ||
	fail "a pinned array or object was deleted"
same_json "$(jq -c '.attribution' <<<"$structural")" "$(jq -c '.attribution' "$pinned")" ||
	fail "a pinned object was deleted"

# A machine-local value that shadows a declared path's parent with a scalar
# leaves the path pinned: the parent is not an object, so the path is not
# defined below and there is nothing to hand over.
echo '{"statusLine": "none"}' >"$work/shadowed.json"
shadowed=$("$overlay" "$pinned" "$work/shadowed.json" "${overridable[@]}")
[ "$(jq -r '.statusLine.command' <<<"$shadowed")" = "$(jq -r '.statusLine.command' "$pinned")" ] ||
	fail "a scalar shadowing the parent deleted the declared path"

# A declared path the machine-local file leaves alone keeps its pinned default.
echo '{"theme": "light"}' >"$work/partial.json"
partial=$("$overlay" "$pinned" "$work/partial.json" "${overridable[@]}")
[ "$(jq -r '.model' <<<"$partial")" = pinned-model ] || fail "unset path lost its pinned default"

# Machine-local files that override nothing degrade to the pinned payload.
# Absorbable ones are a normal transient state and stay quiet; the rest warn,
# because they mean the file needs attention.
check_degraded() {
	local content=$1 expect_warning=$2 out status=0

	printf '%s' "$content" >"$work/degraded.json"
	out=$("$overlay" "$pinned" "$work/degraded.json" "${overridable[@]}" 2>"$work/stderr") || status=$?
	[ "$status" -eq 0 ] || fail "input ($content) exited $status, expected 0"
	same_json "$out" "$(cat "$pinned")" ||
		fail "input ($content) did not degrade to the pinned payload"

	if grep -q 'ignoring unusable' "$work/stderr"; then
		[ "$expect_warning" = warns ] || fail "input ($content) warned but should be absorbed quietly"
	else
		[ "$expect_warning" = quiet ] || fail "input ($content) degraded silently but should warn"
	fi
}

check_degraded '' quiet
check_degraded 'null' quiet
check_degraded 'false' quiet
check_degraded '{}' quiet
check_degraded '{"model": ' warns
check_degraded '["model"]' warns
check_degraded '42' warns
check_degraded '"model"' warns

# Too few arguments is a wiring mistake in the launch wrapper, not a runtime
# condition to absorb.
status=0
"$overlay" "$pinned" >/dev/null 2>&1 || status=$?
[ "$status" -eq 2 ] || fail "missing arguments exited $status, expected 2"

# No overridable paths is a legitimate configuration, not a wiring mistake.
none=$("$overlay" "$pinned" "$work/prefs.json")
same_json "$none" "$(cat "$pinned")" || fail "empty overridable set changed the pinned payload"

echo "settings-overlay: all fixtures passed"
