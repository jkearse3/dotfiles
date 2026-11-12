#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "usage: migrate-test <migrate-neovim-site>" >&2
	exit 2
fi

migrate=$1
root=$(mktemp -d)
trap 'rm -rf -- "$root"' EXIT

site="$root/site"

# Fails unless file `$1` equals stdin byte for byte.
expect_output() {
	cat >"$root/expected-output"
	if ! cmp "$root/expected-output" "$1"; then
		diff -u "$root/expected-output" "$1" >&2 || true
		exit 1
	fi
}

# A missing site directory is a silent no-op.
"$migrate" "$root/absent" >"$root/stdout" 2>"$root/stderr"
expect_output "$root/stdout" </dev/null
expect_output "$root/stderr" </dev/null

mkdir -p \
	"$site/pack/core/opt/plugin/lua" \
	"$site/pack/hm/opt/plugin" \
	"$site/parser" \
	"$site/parser-info" \
	"$site/queries/lua" \
	"$site/spell"
touch \
	"$site/pack/core/opt/plugin/lua/init.lua" \
	"$site/pack/hm/opt/plugin/init.lua" \
	"$site/parser/lua.so" \
	"$site/parser-info/lua.revision" \
	"$site/queries/lua/highlights.scm" \
	"$site/spell/en.utf-8.add" \
	"$site/parser.keep"

"$migrate" "$site" >"$root/stdout" 2>"$root/stderr"

expect_output "$root/stdout" <<EOF
removed $site/pack/core
removed $site/parser
removed $site/parser-info
removed $site/queries
EOF
expect_output "$root/stderr" </dev/null

# Only the four leftovers are gone; Home Manager's pack and other entries stay.
(cd "$site" && find . | LC_ALL=C sort) >"$root/remaining"
expect_output "$root/remaining" <<'EOF'
.
./pack
./pack/hm
./pack/hm/opt
./pack/hm/opt/plugin
./pack/hm/opt/plugin/init.lua
./parser.keep
./spell
./spell/en.utf-8.add
EOF

# A second run changes nothing, so it prints nothing.
"$migrate" "$site" >"$root/stdout" 2>"$root/stderr"
expect_output "$root/stdout" </dev/null
expect_output "$root/stderr" </dev/null

# A leftover that is only partly present is removed alone.
mkdir "$site/queries"
"$migrate" "$site" >"$root/stdout"
expect_output "$root/stdout" <<EOF
removed $site/queries
EOF

echo "ok - migrate-neovim-site"
