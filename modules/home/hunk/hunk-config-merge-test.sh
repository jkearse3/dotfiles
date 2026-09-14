#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "usage: hunk-config-merge-test <hunk-config-merge>" >&2
	exit 2
fi

merge=$1
root=$(mktemp -d)
trap 'rm -rf -- "$root"' EXIT

defaults="$root/defaults.toml"
printf '%s\n' '# managed fallback' 'theme = "tokyo-night"' >"$defaults"

live="$root/new/hunk/config.toml"
mkdir -p "$(dirname "$live")"
printf '%s\n' '{"version":1}' >"$(dirname "$live")/state.json"
cp "$(dirname "$live")/state.json" "$root/state.expected"
"$merge" "$live" "$defaults"
cmp --silent "$defaults" "$live"
cmp --silent "$root/state.expected" "$(dirname "$live")/state.json"
[[ $(stat -c '%a' "$live") == 600 ]]

printf '%s\n' '# personal choice' 'theme = "dracula"' 'mode = "split"' >"$root/existing.toml"
cp "$root/existing.toml" "$root/existing.expected"
"$merge" "$root/existing.toml" "$defaults"
cmp --silent "$root/existing.expected" "$root/existing.toml"

printf '%s\n' '# retain this comment' 'mode = "unified"' '' '[pager]' 'line_numbers = false' >"$root/missing.toml"
"$merge" "$root/missing.toml" "$defaults"
grep -Fqx '# retain this comment' "$root/missing.toml"
grep -Fqx 'theme = "tokyo-night"' "$root/missing.toml"
grep -Fqx '[pager]' "$root/missing.toml"
grep -Fqx 'line_numbers = false' "$root/missing.toml"
theme_line=$(grep -Fn 'theme = "tokyo-night"' "$root/missing.toml" | cut -d: -f1)
pager_line=$(grep -Fn '[pager]' "$root/missing.toml" | cut -d: -f1)
((theme_line < pager_line))
cp "$root/missing.toml" "$root/missing.expected"
"$merge" "$root/missing.toml" "$defaults"
cmp --silent "$root/missing.expected" "$root/missing.toml"

printf '%s\n' 'theme = [' >"$root/malformed.toml"
cp "$root/malformed.toml" "$root/malformed.expected"
if "$merge" "$root/malformed.toml" "$defaults" 2>/dev/null; then
	echo 'expected malformed TOML to fail' >&2
	exit 1
fi
cmp --silent "$root/malformed.expected" "$root/malformed.toml"

printf '%s\n' 'theme = "nord"' >"$root/target.toml"
ln -s "$root/target.toml" "$root/config-link.toml"
"$merge" "$root/config-link.toml" "$defaults"
[[ -L $root/config-link.toml ]]
grep -Fqx 'theme = "nord"' "$root/target.toml"

ln -s "$root/absent-target.toml" "$root/dangling-link.toml"
"$merge" "$root/dangling-link.toml" "$defaults"
[[ -L $root/dangling-link.toml ]]
[[ ! -e $root/absent-target.toml ]]
