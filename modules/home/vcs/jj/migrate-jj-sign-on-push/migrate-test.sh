#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "usage: migrate-test <migrate-jj-sign-on-push>" >&2
	exit 2
fi

migrate=$1
root=$(mktemp -d)
trap 'rm -rf -- "$root"' EXIT

repos="$root/repos"

# Writes stdin to the config of repository `$1`.
write_config() {
	mkdir -p "$repos/$1"
	cat >"$repos/$1/config.toml"
}

# Fails unless the config of repository `$1` equals stdin byte for byte.
expect_config() {
	cat >"$root/expected.toml"
	if ! cmp "$root/expected.toml" "$repos/$1/config.toml"; then
		diff -u "$root/expected.toml" "$repos/$1/config.toml" >&2 || true
		exit 1
	fi
}

# Fails unless file `$1` equals stdin byte for byte.
expect_output() {
	cat >"$root/expected-output"
	if ! cmp "$root/expected-output" "$1"; then
		diff -u "$root/expected-output" "$1" >&2 || true
		exit 1
	fi
}

# A missing repos directory is a silent no-op.
"$migrate" "$root/absent" >"$root/stdout" 2>"$root/stderr"
expect_output "$root/stdout" </dev/null
expect_output "$root/stderr" </dev/null

write_config a-true <<'EOF'
# Repository identity.
[user]
name = "Test"

[git]
# Kept comment.
sign-on-push = true # Old key.
private-commits = "none()"
EOF

write_config b-false <<'EOF'
[git]
sign-on-push = false
EOF

write_config c-revsets-table <<'EOF'
[git]
sign-on-push = true

[revsets]
log = "@"
EOF

write_config d-revset-kept <<'EOF'
[git]
sign-on-push = true

[revsets]
git-sign-on-push = "all()"
EOF

write_config e-untouched <<'EOF'
[user]
name = "Untouched"
EOF
chmod 640 "$repos/e-untouched/config.toml"
cp -p "$repos/e-untouched/config.toml" "$root/untouched.toml"

write_config f-dotted <<'EOF'
git.sign-on-push = true
EOF

write_config g-malformed <<'EOF'
[git
sign-on-push = true
EOF

chmod 600 "$repos/a-true/config.toml"

"$migrate" "$repos" >"$root/stdout" 2>"$root/stderr"

expect_output "$root/stdout" <<EOF
$repos/a-true/config.toml: removed git.sign-on-push = true, set revsets.git-sign-on-push = "~signed() & mine()"
$repos/b-false/config.toml: removed git.sign-on-push = false, set revsets.git-sign-on-push = "none()"
$repos/c-revsets-table/config.toml: removed git.sign-on-push = true, set revsets.git-sign-on-push = "~signed() & mine()"
$repos/d-revset-kept/config.toml: removed git.sign-on-push = true, kept the existing revsets.git-sign-on-push
EOF

grep -Fq "$repos/f-dotted/config.toml" "$root/stderr"
grep -Fq "$repos/g-malformed/config.toml" "$root/stderr"
[[ $(wc -l <"$root/stderr") -eq 2 ]]

expect_config a-true <<'EOF'
# Repository identity.
[user]
name = "Test"

[git]
# Kept comment.
private-commits = "none()"

[revsets]
git-sign-on-push = "~signed() & mine()"
EOF
[[ $(stat -c '%a' "$repos/a-true/config.toml") == 600 ]]

expect_config b-false <<'EOF'
[git]

[revsets]
git-sign-on-push = "none()"
EOF

expect_config c-revsets-table <<'EOF'
[git]

[revsets]
git-sign-on-push = "~signed() & mine()"
log = "@"
EOF

expect_config d-revset-kept <<'EOF'
[git]

[revsets]
git-sign-on-push = "all()"
EOF

cmp "$root/untouched.toml" "$repos/e-untouched/config.toml"
[[ $(stat -c '%a' "$repos/e-untouched/config.toml") == 640 ]]

expect_config f-dotted <<'EOF'
git.sign-on-push = true
EOF

expect_config g-malformed <<'EOF'
[git
sign-on-push = true
EOF

# A second run changes nothing, so it prints nothing on standard output.
"$migrate" "$repos" >"$root/stdout" 2>/dev/null
expect_output "$root/stdout" </dev/null

echo "ok - migrate-jj-sign-on-push"
