#!/usr/bin/env bash

# Tests how dotfiles-apps validates its arguments and selects a blueprint, up
# to the point where it would start nh, how the switch apps refuse a linked Git
# worktree, and which arguments package-update passes to the package updaters,
# with real Git repositories made with `git` from PATH. Usage: arguments-test.sh
# <dotfiles-apps executable> <blueprint ID from the flake's inventory>. Runs
# with HOME and XDG_CONFIG_HOME in a temporary directory, and keeps git from
# finding repositories above it. `flake-update-test.sh` tests flake-update
# itself.

set -uo pipefail

app=$1
blueprint_id=$2

failures=0
work="$(mktemp -d)"
repo="$work/repo"
mkdir -p "$repo/flake/blueprints" "$work/home" "$work/config"
touch "$repo/flake.nix" "$repo/flake/blueprints/default.nix"
export HOME="$work/home"
export XDG_CONFIG_HOME="$work/config"
export GIT_CEILING_DIRECTORIES="$work"
unset DOTFILES_PRIVATE_LOCAL

# Runs the app from `directory` with the remaining arguments and records its
# exit status in `status` and its combined output in `output`.
run_app() {
	local directory=$1
	shift
	output="$(cd "$directory" && "$app" "$@" 2>&1)"
	status=$?
}

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

# Checks that the last run printed a line containing `expected_text`, whatever
# its exit status.
expect_output() {
	local name=$1
	local expected_text=$2
	if [[ $output == *"$expected_text"* ]]; then
		echo "ok - $name"
	else
		echo "not ok - $name: output:" >&2
		printf '%s\n' "$output" >&2
		failures=$((failures + 1))
	fi
}

run_app "$repo" build-home --help
expect "--help prints usage and exits 0" 0 "usage: nix run .#build-home"

run_app "$repo" build-home --bogus
expect "an unknown option exits 2" 2 "build-home does not accept '--bogus'"

run_app "$repo" build-system --dry-run
expect "--dry-run is rejected for system apps" 2 "build-system does not accept '--dry-run'"

run_app "$repo" build-home --blueprint
expect "--blueprint without an ID exits 2" 2 "--blueprint requires a blueprint ID"

run_app "$work" build-home --blueprint "$blueprint_id"
expect "running outside the repository root fails" 1 "must run from the dotfiles repository root"

run_app "$repo" build-home
expect "a missing marker names how to list and bootstrap" 1 "nix run .#switch-home -- --blueprint <blueprint-id>"

mkdir -p "$XDG_CONFIG_HOME/dotfiles"
printf ' %s\n' "$blueprint_id" >"$XDG_CONFIG_HOME/dotfiles/blueprint-id"
run_app "$repo" build-system
expect "a padded marker names an unknown blueprint" 1 "unknown blueprint ' $blueprint_id'"
rm "$XDG_CONFIG_HOME/dotfiles/blueprint-id"

run_app "$repo" build-home --blueprint nonexistent
expect "an unknown blueprint fails" 1 "unknown blueprint 'nonexistent'"

DOTFILES_PRIVATE_LOCAL="$work/missing" run_app "$repo" build-home --blueprint "$blueprint_id"
expect "an invalid DOTFILES_PRIVATE_LOCAL fails" 1 "DOTFILES_PRIVATE_LOCAL does not identify a flake checkout"

run_app "$repo" build-home --allow-worktree
expect "--allow-worktree is rejected for build apps" 2 "build-home does not accept '--allow-worktree'"

run_app "$repo" switch-home --help
expect "switch-home --help lists --allow-worktree" 0 "--allow-worktree"

run_app "$repo" switch-system --help
expect "switch-system --help lists --allow-worktree" 0 "--allow-worktree"

run_app "$work" switch-home
expect "the repository-root check comes before the worktree guard" 1 "must run from the dotfiles repository root"

# The switch cases select a nonexistent blueprint, so a run that passes the
# worktree guard stops at blueprint selection before nh.
run_app "$repo" switch-home --blueprint nonexistent
expect "switching outside a Git repository fails closed" 1 "pass --allow-worktree"

run_app "$repo" switch-home --allow-worktree --blueprint nonexistent
expect "--allow-worktree skips the guard outside a Git repository" 1 "unknown blueprint 'nonexistent'"

# A main checkout with one linked worktree.
main="$work/main"
mkdir -p "$main/flake/blueprints"
touch "$main/flake.nix" "$main/flake/blueprints/default.nix"
git -C "$main" init -q
git -C "$main" add flake.nix flake/blueprints/default.nix
git -C "$main" -c user.name=Test -c user.email=test@example.com commit -q -m initial
git -C "$main" worktree add -q --relative-paths --detach "$work/linked"
main_physical="$(cd "$main" && pwd -P)"

run_app "$main" switch-system --blueprint nonexistent
expect "switching from the main checkout passes the guard" 1 "unknown blueprint 'nonexistent'"

run_app "$work/linked" switch-home --blueprint nonexistent
expect "switch-home from a linked worktree names the main checkout" 1 "must run from the main checkout $main_physical,"

run_app "$work/linked" switch-system --blueprint nonexistent
expect "switch-system from a linked worktree names the main checkout" 1 "must run from the main checkout $main_physical,"

run_app "$work/linked" switch-home --allow-worktree --blueprint nonexistent
expect "--allow-worktree switches from a linked worktree" 1 "unknown blueprint 'nonexistent'"

run_app "$work/linked" build-home --blueprint nonexistent
expect "build apps run from a linked worktree" 1 "unknown blueprint 'nonexistent'"

# Nix is not on PATH here, so nh fails right after selection.
run_app "$repo" build-home --blueprint "$blueprint_id"
expect_output "--blueprint selects the blueprint" "Selected blueprint '$blueprint_id' from --blueprint"

printf '%s\n' "$blueprint_id" >"$XDG_CONFIG_HOME/dotfiles/blueprint-id"
run_app "$repo" build-system
expect_output "the marker selects the blueprint" "Selected blueprint '$blueprint_id' from marker"

run_app "$repo" flake-update --dry-run
expect "--dry-run is rejected for flake-update" 2 "flake-update does not accept '--dry-run'"

run_app "$repo" flake-update --help
expect "flake-update --help exits 0" 0 "usage: nix run .#flake-update"

run_app "$repo" package-update --blueprint x
expect "--blueprint is rejected for package-update" 2 "package-update does not accept '--blueprint'"

run_app "$repo" package-update --dry-run
expect "package-update without updaters succeeds" 0 "No package updaters found"

# A stub updater, like the real ones started through `/usr/bin/env bash`,
# echoes the arguments package-update passes it.
mkdir -p "$repo/packages/stub"
cat >"$repo/packages/stub/update.sh" <<'EOF'
#!/usr/bin/env bash
echo "stub updater args: $*."
EOF
chmod +x "$repo/packages/stub/update.sh"
run_app "$repo" package-update --dry-run
expect "package-update --dry-run passes --latest --dry-run" 0 "stub updater args: --latest --dry-run."
run_app "$repo" package-update
expect "package-update without --dry-run passes --latest alone" 0 "stub updater args: --latest."

if [[ $failures -ne 0 ]]; then
	echo "$failures case(s) failed" >&2
	exit 1
fi
