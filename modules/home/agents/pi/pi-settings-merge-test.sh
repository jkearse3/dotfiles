#!/usr/bin/env bash

# Fixtures for pi-settings-merge. A regression here loses settings pi wrote at
# runtime silently, so these run at build time rather than at activation.
#
# usage: pi-settings-merge-test <path-to-pi-settings-merge>

set -euo pipefail

merge=${1:?usage: pi-settings-merge-test <path-to-pi-settings-merge>}

seed=$(mktemp)
cat >"$seed" <<'JSON'
{
  "theme": "dark",
  "defaultModel": "gpt-5.6-sol",
  "tuiMode": "fullscreen",
  "lastChangelogVersion": "999.999.999"
}
JSON

work=$(mktemp -d)
export HOME="$work/home"
agent="$HOME/.pi/agent"
mkdir -p "$agent"

failures=0

# Each case seeds the live file, the Nix-declared list, and the previous
# generation's recorded list, then asserts a jq predicate over the result.
check() {
	local name=$1 live=$2 declared=$3 previous=$4 predicate=$5
	local settings="$agent/settings.json"
	local declared_file="$work/declared.json" previous_file="$work/previous.json"

	rm -f "$settings"
	if [[ $live != "<missing>" ]]; then
		printf '%s\n' "$live" >"$settings"
	fi
	printf '%s\n' "$declared" >"$declared_file"

	if [[ $previous == "<missing>" ]]; then
		rm -f "$previous_file"
	else
		printf '%s\n' "$previous" >"$previous_file"
	fi

	if ! "$merge" "$settings" "$seed" "$declared_file" "$previous_file"; then
		echo "FAIL $name: merge exited nonzero" >&2
		failures=$((failures + 1))
		return
	fi

	local mode
	mode=$(stat -c '%a' "$settings" 2>/dev/null || stat -f '%Lp' "$settings")
	if [[ $mode != 600 ]]; then
		echo "FAIL $name: expected mode 600, got $mode" >&2
		failures=$((failures + 1))
	fi

	if ! jq -e "$predicate" "$settings" >/dev/null; then
		echo "FAIL $name: predicate rejected $(cat "$settings")" >&2
		failures=$((failures + 1))
		return
	fi
	echo "ok   $name"
}

check "missing live file is seeded" \
	'<missing>' '[]' '<missing>' \
	'.theme == "dark" and .defaultModel == "gpt-5.6-sol" and .tuiMode == "fullscreen" and (has("packages") | not)'

check "empty object takes the whole seed" \
	'{}' '[]' '[]' \
	'.theme == "dark" and .lastChangelogVersion == "999.999.999"'

check "absent packages key with a declared entry" \
	'{"theme":"light"}' '["npm:pi-thing"]' '[]' \
	'.packages == ["npm:pi-thing"]'

check "null packages key does not abort" \
	'{"packages":null}' '["npm:pi-thing"]' '[]' \
	'.packages == ["npm:pi-thing"]'

check "missing previous generation attributes nothing to Nix" \
	'{"packages":["npm:installed-by-hand"]}' '[]' '<missing>' \
	'.packages == ["npm:installed-by-hand"]'

check "pi install survives alongside a declared entry" \
	'{"packages":["npm:declared","../../../thirdparty-pkg"]}' \
	'["npm:declared"]' '["npm:declared"]' \
	'.packages == ["npm:declared","../../../thirdparty-pkg"]'

# Pi rewrites an installed local path to be relative to the agent directory,
# so the declared absolute form and the stored relative form must compare equal.
# Three levels up from $HOME/.pi/agent is the parent of $HOME.
local_pkg="$(dirname -- "$HOME")/thirdparty-pkg"
check "a relative local path matches its absolute declaration" \
	'{"packages":["../../../thirdparty-pkg"]}' \
	"[\"$local_pkg\"]" "[\"$local_pkg\"]" \
	'.packages == ["../../../thirdparty-pkg"]'

check "an entry pi promoted to object form is kept, not duplicated" \
	'{"packages":[{"source":"npm:declared","skills":["one"]}]}' \
	'["npm:declared"]' '["npm:declared"]' \
	'.packages == [{"source":"npm:declared","skills":["one"]}]'

check "an entry dropped from Nix is removed" \
	'{"packages":["npm:declared","npm:installed-by-hand"]}' \
	'[]' '["npm:declared"]' \
	'.packages == ["npm:installed-by-hand"]'

check "in-app model and TUI mode choices survive the seed" \
	'{"defaultModel":"claude-opus-5","theme":"light","tuiMode":"regular"}' '[]' '[]' \
	'.defaultModel == "claude-opus-5" and .theme == "light" and .tuiMode == "regular" and .lastChangelogVersion == "999.999.999"'

# Pi matches an npm source by bare name and rewrites the stored entry in place,
# so a re-install at another version must stay one package rather than becoming
# a second entry beside the declared spec.
check "a version pi stored back is not a second package" \
	'{"packages":["npm:@example/pack@2.0.0"]}' \
	'["npm:@example/pack@1.0.0"]' '["npm:@example/pack@1.0.0"]' \
	'.packages == ["npm:@example/pack@2.0.0"]'

check "ssh and https spellings of one repository are one package" \
	'{"packages":["git:git@github.com:example/pack.git"]}' \
	'["https://github.com/example/pack"]' '["https://github.com/example/pack"]' \
	'.packages == ["git:git@github.com:example/pack.git"]'

# Pi splits a git ref on the first @ in the path as well as on #, so a re-pin
# must land on the existing entry rather than beside it.
check "an at-pinned git ref is not part of the identity" \
	'{"packages":["https://github.com/example/pack@v2"]}' \
	'["https://github.com/example/pack@v1"]' '["https://github.com/example/pack@v1"]' \
	'.packages == ["https://github.com/example/pack@v2"]'

# In a URL the colon introduces a port, which pi drops with the rest of the
# authority; in an scp-style source the same colon separates host from path, so
# a numeric first segment stays part of the path. The two must not converge.
check "a url port is not part of the identity" \
	'{"packages":["ssh://git@host.example:2222/e/p.git"]}' \
	'["https://host.example/e/p"]' '["https://host.example/e/p"]' \
	'.packages == ["ssh://git@host.example:2222/e/p.git"]'

check "an ipv6 host survives its own colons" \
	'{"packages":["https://[2001:db8::1]:8443/e/p"]}' \
	'["ssh://git@[2001:db8::1]/e/p.git"]' '["ssh://git@[2001:db8::1]/e/p.git"]' \
	'.packages == ["https://[2001:db8::1]:8443/e/p"]'

check "an scp numeric path segment stays in the identity" \
	'{"packages":["git:git@host.example:2222/e/p"]}' \
	'["https://host.example/e/p"]' '["https://host.example/e/p"]' \
	'.packages == ["git:git@host.example:2222/e/p","https://host.example/e/p"]'

check "two live entries for one Nix-owned package collapse to one" \
	'{"packages":["npm:pack@1.0.0","npm:pack@2.0.0"]}' \
	'["npm:pack@3.0.0"]' '["npm:pack@1.0.0"]' \
	'.packages == ["npm:pack@3.0.0"]'

check "duplicates Nix never placed are left alone" \
	'{"packages":["npm:hand@1.0.0","npm:hand@2.0.0"]}' \
	'[]' '[]' \
	'.packages == ["npm:hand@1.0.0","npm:hand@2.0.0"]'

check "an edit Nix made to a declared entry reaches the live file" \
	'{"packages":[{"source":"npm:pack","skills":["review"]}]}' \
	'[{"source":"npm:pack","skills":["review","test"]}]' \
	'[{"source":"npm:pack","skills":["review"]}]' \
	'.packages == [{"source":"npm:pack","skills":["review","test"]}]'

check "keys in neither bucket pass through" \
	'{"someFutureKey":{"nested":1}}' '[]' '[]' \
	'.someFutureKey.nested == 1'

if [[ $failures -gt 0 ]]; then
	echo "$failures fixture(s) failed" >&2
	exit 1
fi
echo "all pi-settings-merge fixtures passed"
