#!/usr/bin/env bash

# Tests how flake-update checks, resumes, guards, and describes a dependency
# update, running it in a real jj repository made with `jj` from PATH, with
# stub `nix` and `nix-store` commands that log their arguments and serve fake
# configurations. Usage: flake-update-test.sh <dotfiles-apps executable>
# <blueprint ID from the flake's inventory> <its Nix system> <its Rust target
# triple>. Runs with HOME, XDG_CONFIG_HOME, and the jj config in a temporary
# directory.

set -uo pipefail

app=$1
blueprint_id=$2
blueprint_platform=$3
blueprint_rust_target=$4

failures=0
work="$(mktemp -d)"
mkdir -p "$work/home" "$work/config/dotfiles"
export HOME="$work/home"
export XDG_CONFIG_HOME="$work/config"
export GIT_CEILING_DIRECTORIES="$work"
unset DOTFILES_PRIVATE_LOCAL
printf '%s\n' "$blueprint_id" >"$XDG_CONFIG_HOME/dotfiles/blueprint-id"

# Checks that the last run exited with `expected_status` and printed a line
# containing `expected_text`.
expect() {
	local name=$1
	local expected_status=$2
	local expected_text=$3
	if [[ $status -eq $expected_status && $output == *"$expected_text"* ]]; then
		echo "ok - $name"
	else
		echo "not ok - $name: status $status, output:" >&2
		printf '%s\n' "$output" >&2
		failures=$((failures + 1))
	fi
}

# The flake-update cases run in a real jj repository whose parent revision holds
# `old.lock` as flake.lock and a stub package pinned at version 1.0. A stub
# `nix` logs each call's arguments as one line: `flake update` copies
# STUB_NEW_LOCK over flake.lock, a `--print-out-paths` build prints a fake
# configuration from `$work/store`, old for the parent revision and new
# otherwise, and any call whose arguments contain STUB_NIX_FAIL_ON fails. A
# stub `nix-store` prints the closures recorded in those fake
# configurations. The stub updater pins STUB_PIN_VERSION, or fails when it is
# `fail`.
update_repo="$work/update-repo"
mkdir -p "$update_repo/flake/blueprints" "$update_repo/packages/stub" "$work/bin"
touch "$update_repo/flake.nix" "$update_repo/flake/blueprints/default.nix"
cat >"$work/old.lock" <<'EOF'
{
  "nodes": {
    "nixpkgs": { "locked": { "lastModified": 1762041600, "rev": "1111111aaaaaaa", "type": "github" } },
    "tools": {
      "inputs": { "nixpkgs": "tools-nixpkgs", "shared": ["nixpkgs"] },
      "locked": { "lastModified": 1762041600, "rev": "2222222bbbbbbb", "type": "github" }
    },
    "tools-nixpkgs": { "locked": { "lastModified": 1762041600, "rev": "3333333ccccccc", "type": "github" } },
    "root": { "inputs": { "nixpkgs": "nixpkgs", "tools": "tools" } }
  },
  "root": "root",
  "version": 7
}
EOF
sed -e 's/1111111aaaaaaa/4444444ddddddd/' -e '0,/1762041600/s//1762646400/' \
	-e 's/3333333ccccccc/5555555eeeeeee/' "$work/old.lock" >"$work/new.lock"
cp "$work/old.lock" "$update_repo/flake.lock"
printf '{\n  version = "1.0";\n}\n' >"$update_repo/packages/stub/package.nix"
cat >"$update_repo/packages/stub/update.sh" <<'EOF'
#!/usr/bin/env bash
[[ $STUB_PIN_VERSION != fail ]] || exit 1
printf '{\n  version = "%s";\n}\n' "$STUB_PIN_VERSION" >"$(dirname "$0")/package.nix"
EOF
chmod +x "$update_repo/packages/stub/update.sh"

# Fake configurations: each holds the closure of its `home-path` or `sw`, one
# store path per line in `refs`. Besides plain version changes, the closures
# hold a wrapper without a version, named like its package, that only the new
# closure has (pi); a library at two versions of which one changes (nixlib);
# toolchain components named with the blueprint's own target triple that move
# together (cargo, rustc); a component for another target (rust-std for
# wasm32); and versions whose text order differs from their numeric order
# (multi).
store="$work/store"
for generation in old-home old-system new-home new-system; do
	mkdir -p "$store/$generation" "$store/$generation-packages"
	link=home-path
	[[ $generation == *-system ]] && link=sw
	ln -s "$store/$generation-packages" "$store/$generation/$link"
done
printf '%s\n' /nix/store/a-curl-8.23.0-bin /nix/store/b-jujutsu-0.46.0 /nix/store/c-legacy-2.0 \
	/nix/store/k-jujutsu-0.46.0-fish-completions /nix/store/n-pi-1.5.1 \
	/nix/store/o-nixlib-2.34.9 /nix/store/p-nixlib-2.35.3 \
	"/nix/store/q-cargo-1.99.1-$blueprint_rust_target" "/nix/store/r-rustc-1.99.1-$blueprint_rust_target" \
	/nix/store/s-rust-std-1.99.1-wasm32-unknown-unknown /nix/store/t-multi-0.9 \
	>"$store/old-home-packages/refs"
printf '%s\n' /nix/store/d-curl-8.23.0-bin /nix/store/e-jujutsu-0.47.1 /nix/store/f-ruff-0.17.5 \
	/nix/store/l-jujutsu-0.47.1-fish-completions /nix/store/u-pi /nix/store/v-pi-1.5.2 \
	/nix/store/o-nixlib-2.34.9 /nix/store/w-nixlib-2.35.6 \
	"/nix/store/x-cargo-1.100.0-$blueprint_rust_target" "/nix/store/y-rustc-1.100.0-$blueprint_rust_target" \
	/nix/store/z-rust-std-1.100.0-wasm32-unknown-unknown /nix/store/0-multi-1.10.0 /nix/store/1-multi-1.9.0 \
	>"$store/new-home-packages/refs"
printf '%s\n' /nix/store/g-zsh-5.9.2 /nix/store/h-zsh-5.9.2-man >"$store/old-system-packages/refs"
printf '%s\n' /nix/store/i-zsh-5.9.3 /nix/store/j-zsh-5.9.3-man >"$store/new-system-packages/refs"

nix_log="$work/nix.log"
cat >"$work/bin/nix" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$nix_log"
if [[ -n \${STUB_NIX_FAIL_ON-} && "\$*" == *"\$STUB_NIX_FAIL_ON"* ]]; then
	exit 1
fi
case "\$*" in
"flake update"*) cp "\$STUB_NEW_LOCK" flake.lock ;;
*--print-out-paths*)
	age=new
	[[ "\$*" == *git+file:* ]] && age=old
	kind=home
	[[ "\$*" == *darwinConfigurations* ]] && kind=system
	echo "$store/\$age-\$kind"
	;;
esac
if [[ -n \${STUB_NIX_TOUCH_ON-} && "\$*" == *"\$STUB_NIX_TOUCH_ON"* ]]; then
	echo edited >stray-edit.txt
fi
EOF
cat >"$work/bin/nix-store" <<'EOF'
#!/usr/bin/env bash
shift 2
for path in "$@"; do cat "$path/refs"; done
EOF
chmod +x "$work/bin/nix" "$work/bin/nix-store"
stub_path="$work/bin:$PATH"

export JJ_CONFIG="$work/jj.toml"
printf '[user]\nname = "Test"\nemail = "test@example.com"\n' >"$JJ_CONFIG"
(cd "$update_repo" && jj git init --quiet && jj commit --quiet -m "initial")
initial_change="$(jj -R "$update_repo" log -r @- --no-graph -T change_id)"

# Runs jj in the update repository.
update_jj() {
	jj -R "$update_repo" "$@"
}

# Runs flake-update in the update repository with the stubs first on PATH,
# after emptying the nix log. Its arguments are environment assignments that
# override the stub defaults: the new lock and pin version 1.1.
run_flake_update() {
	: >"$nix_log"
	output="$(cd "$update_repo" &&
		env STUB_NEW_LOCK="$work/new.lock" STUB_PIN_VERSION=1.1 PATH="$stub_path" "$@" "$app" flake-update 2>&1)"
	status=$?
}

# Abandons everything above the initial revision and starts an empty change on
# it.
reset_update_repo() {
	update_jj new --quiet "$initial_change"
	update_jj abandon --quiet "$initial_change+:: ~ @"
}

# Prints the steps the stub `nix` ran, in order, on one line.
nix_steps() {
	local steps=() line
	while IFS= read -r line; do
		case $line in
		"flake update"*) steps+=(update) ;;
		*.#eval-blueprints*) steps+=(eval-blueprints) ;;
		"flake check"*) steps+=(flake-check) ;;
		*--print-out-paths*git+file:*) steps+=(old-config) ;;
		*--print-out-paths*) steps+=(new-config) ;;
		*.#homeConfigurations.*.activationPackage*) steps+=(home-build) ;;
		*.#darwinConfigurations.*.system*) steps+=(system-build) ;;
		*) steps+=("unexpected: $line") ;;
		esac
	done <"$nix_log"
	echo "${steps[*]}"
}

# Checks that `actual` equals `expected`.
expect_equal() {
	local name=$1
	local expected=$2
	local actual=$3
	if [[ $actual == "$expected" ]]; then
		echo "ok - $name"
	else
		echo "not ok - $name: expected:" >&2
		printf '%s\n' "$expected" >&2
		echo "got:" >&2
		printf '%s\n' "$actual" >&2
		failures=$((failures + 1))
	fi
}

# Prints the full description of `revision` in the update repository.
description_of() {
	update_jj log -r "$1" --no-graph -T description
}

rm "$XDG_CONFIG_HOME/dotfiles/blueprint-id"
reset_update_repo
run_flake_update
expect "flake-update without a marker names how to bootstrap" 1 "nix run .#switch-home -- --blueprint <blueprint-id>"
expect_equal "flake-update without a marker runs no nix" "" "$(cat "$nix_log")"
printf '%s\n' "$blueprint_id" >"$XDG_CONFIG_HOME/dotfiles/blueprint-id"

full_checks="eval-blueprints flake-check home-build system-build old-config old-config new-config new-config"
expected_description="build(nix): update dependencies

Flake inputs:
- nixpkgs: 1111111 (2025-11-02) -> 4444444 (2025-11-09)
- tools/nixpkgs: 3333333 (2025-11-02) -> 5555555 (2025-11-02)

Package pins:
- stub: 1.0 -> 1.1

Package versions in the $blueprint_id blueprint ($blueprint_platform):
- cargo, rustc: 1.99.1 -> 1.100.0
- jujutsu: 0.46.0 -> 0.47.1
- legacy: removed 2.0
- multi: 0.9 -> 1.9.0, 1.10.0
- nixlib: 2.35.3 -> 2.35.6
- pi: 1.5.1 -> 1.5.2
- ruff: added 0.17.5
- rust-std: 1.99.1-wasm32-unknown-unknown ->
  1.100.0-wasm32-unknown-unknown
- zsh: 5.9.2 -> 5.9.3"

reset_update_repo
run_flake_update
expect "flake-update commits once every check passes" 0 "==> Committed the dependency update as"
expect_equal "flake-update updates, checks, then reads both configurations" "update $full_checks" "$(nix_steps)"
expect_equal "the commit lists changed inputs, pins, and package versions" "$expected_description" "$(description_of @-)"
expect_equal "the commit leaves an empty change on top" "true" "$(update_jj log -r @ --no-graph -T 'empty && !description')"

reset_update_repo
run_flake_update STUB_NEW_LOCK="$work/old.lock" STUB_PIN_VERSION=1.0
expect "unchanged dependencies commit nothing" 0 "Dependencies unchanged; nothing to commit"
expect_equal "unchanged dependencies run no checks" "update" "$(nix_steps)"
expect_equal "unchanged dependencies leave @ on the initial revision" "initial" \
	"$(update_jj log -r @- --no-graph -T 'description.first_line()')"

reset_update_repo
run_flake_update STUB_PIN_VERSION=fail
expect "a failing updater restores @" 1 "error: updating dependencies failed; @ is restored to its parent"
expect_equal "a failing updater leaves @ empty" "true" "$(update_jj log -r @ --no-graph -T empty)"

reset_update_repo
run_flake_update STUB_NIX_FAIL_ON="flake check"
expect "a failing flake check leaves the update in @" 1 "error: nix flake check failed."
expect_equal "a failing flake check stops before the builds" "update eval-blueprints flake-check" "$(nix_steps)"
expect_equal "a failing flake check leaves @ described as the update" "build(nix): update dependencies" "$(description_of @)"

echo fixed >"$update_repo/fix.nix"
run_flake_update
expect "a fix without an explanation is refused" 1 "also changes files beyond the dependency pins:
  fix.nix"
expect_equal "a fix without an explanation runs no checks" "" "$(nix_steps)"

update_jj describe --quiet -m "build(nix): update dependencies

The fix explains itself here."
run_flake_update
expect "rerunning resumes the update in @" 0 "Resuming the dependency update in @"
expect_equal "resuming reruns the checks without updating" "$full_checks" "$(nix_steps)"
expected_resumed="build(nix): update dependencies

The fix explains itself here.

${expected_description#build(nix): update dependencies$'\n\n'}"
expect_equal "resuming keeps the written explanation before the lists" "$expected_resumed" "$(description_of @-)"

# jj signs every commit it writes with a signing program that always fails.
printf '[signing]\nbehavior = "own"\nbackend = "ssh"\nkey = "unused"\nbackends.ssh.program = "false"\n' \
	>"$work/jj-failing-signing.toml"
reset_update_repo
update_jj describe --quiet -m "build(nix): update dependencies"
cp "$work/new.lock" "$update_repo/flake.lock"
update_jj status >/dev/null # Snapshots the lock before signing starts failing.
run_flake_update JJ_CONFIG="$JJ_CONFIG:$work/jj-failing-signing.toml"
expect "a failing commit leaves the update in @" 1 "error: committing the update failed."
expect_equal "a failing commit keeps @ described as the update" "build(nix): update dependencies" "$(description_of @)"

reset_update_repo
run_flake_update STUB_NIX_TOUCH_ON=darwinConfigurations
expect "a file changed during the checks blocks the commit" 1 "files in @ changed while the checks ran"
expect_equal "a file changed during the checks leaves the update in @" "build(nix): update dependencies" "$(description_of @)"

reset_update_repo
run_flake_update STUB_NIX_FAIL_ON=git+file:
expect "an unbuildable parent still commits" 0 "warning: could not build the configurations of @-"
expect_equal "an unbuildable parent omits package versions" "${expected_description%%$'\n\nPackage versions'*}" "$(description_of @-)"

mkdir -p "$work/private"
touch "$work/private/flake.nix"
reset_update_repo
run_flake_update DOTFILES_PRIVATE_LOCAL="$work/private"
expect_equal "DOTFILES_PRIVATE_LOCAL stays out of flake.lock" "0" "$(grep -c '^flake update .*--override-input' "$nix_log")"
expect_equal "DOTFILES_PRIVATE_LOCAL reaches the flake check" "1" \
	"$(grep -c "^flake check .*--override-input dotfiles-private path:$work/private" "$nix_log")"

if [[ $failures -ne 0 ]]; then
	echo "$failures case(s) failed" >&2
	exit 1
fi
