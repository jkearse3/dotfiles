#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "usage: migrate-test <migrate-jj-signing-key>" >&2
	exit 2
fi

migrate=$1
root=$(mktemp -d)
trap 'rm -rf -- "$root"' EXIT

repos="$root/repos"
old=/home/test/.ssh/github_personal_signing.pub
new=$root/git_secure_enclave

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
"$migrate" "$root/absent" "$old" "$new" >"$root/stdout" 2>"$root/stderr"
expect_output "$root/stdout" </dev/null
expect_output "$root/stderr" </dev/null

# The shape jjx writes.
write_config a-jjx <<EOF
#:schema https://docs.jj-vcs.dev/latest/config-schema.json

[user]
name = "Test"

[signing]
backend = "ssh"
key = "$old" # Comment kept.

[revsets]
git-sign-on-push = "~signed() & mine()"
EOF

write_config b-other-key <<'EOF'
[signing]
backend = "ssh"
key = "/home/test/.ssh/some_other_key.pub"
EOF

write_config c-no-signing-key <<'EOF'
[signing]
backend = "none"
EOF

write_config d-dotted <<EOF
signing.key = "$old"
EOF

# Names the old key only outside [signing], so it is not migrated.
write_config e-elsewhere <<EOF
[other]
key = "$old"
EOF

# Names the old key in a shape the text edit does not recognize.
write_config f-literal-string <<EOF
[signing]
key = '$old'
EOF

cp "$repos/a-jjx/config.toml" "$root/a.orig"
cp "$repos/b-other-key/config.toml" "$root/b.orig"
cp "$repos/d-dotted/config.toml" "$root/d.orig"
cp "$repos/e-elsewhere/config.toml" "$root/e.orig"
cp "$repos/f-literal-string/config.toml" "$root/f.orig"
chmod 640 "$repos/a-jjx/config.toml"

# While the new key does not exist, nothing changes, and one line counts the
# configs still naming the old key: a, d, and f.
"$migrate" "$repos" "$old" "$new" >"$root/stdout" 2>"$root/stderr"
expect_output "$root/stdout" </dev/null
expect_output "$root/stderr" <<EOF
migrate-jj-signing-key: $new does not exist yet; left 3 repository config(s) naming $old unchanged until a run after it does
EOF
for repository in a-jjx b-other-key d-dotted e-elsewhere f-literal-string; do
	expect_config "$repository" <"$root/${repository%%-*}.orig"
done

# Without a config naming the old key, a missing new key prints nothing.
mkdir "$root/others"
cp -R "$repos/b-other-key" "$repos/c-no-signing-key" "$root/others/"
"$migrate" "$root/others" "$old" "$new" >"$root/stdout" 2>"$root/stderr"
expect_output "$root/stdout" </dev/null
expect_output "$root/stderr" </dev/null

touch "$new"
"$migrate" "$repos" "$old" "$new" >"$root/stdout" 2>"$root/stderr"

expect_config a-jjx <<EOF
#:schema https://docs.jj-vcs.dev/latest/config-schema.json

[user]
name = "Test"

[signing]
backend = "ssh"
key = "$new" # Comment kept.

[revsets]
git-sign-on-push = "~signed() & mine()"
EOF
[[ $(stat -c %a "$repos/a-jjx/config.toml" 2>/dev/null || stat -f %Lp "$repos/a-jjx/config.toml") == 640 ]]
expect_config b-other-key <"$root/b.orig"
expect_config c-no-signing-key <<'EOF'
[signing]
backend = "none"
EOF
expect_config d-dotted <<EOF
signing.key = "$new"
EOF
expect_config e-elsewhere <"$root/e.orig"
expect_config f-literal-string <"$root/f.orig"

expect_output "$root/stdout" <<EOF
$repos/a-jjx/config.toml: signing.key $old -> $new
$repos/d-dotted/config.toml: signing.key $old -> $new
EOF
expect_output "$root/stderr" <<EOF
migrate-jj-signing-key: $repos/f-literal-string/config.toml: signing.key is not set as a plain line under [signing]; left unchanged
EOF

# A second run changes and prints nothing more.
"$migrate" "$repos" "$old" "$new" >"$root/stdout" 2>"$root/stderr"
expect_output "$root/stdout" </dev/null
expect_output "$root/stderr" <<EOF
migrate-jj-signing-key: $repos/f-literal-string/config.toml: signing.key is not set as a plain line under [signing]; left unchanged
EOF
