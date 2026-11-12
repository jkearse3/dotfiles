#!/usr/bin/env bash

# Tests how dotfiles-apps validates its arguments and selects a blueprint, up
# to the point where it would start nh, which arguments package-update passes
# to the package updaters, and which checks flake-update runs before it
# commits, with stub `nix` and `jj` commands that log their arguments. Usage:
# arguments-test.sh <dotfiles-apps executable> <blueprint ID from the flake's
# inventory>. Runs with HOME and XDG_CONFIG_HOME in a temporary directory.

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

# Stub `nix` and `jj` commands for the flake-update cases log each call's
# arguments as one line. The `jj` stub reports an empty working copy and a
# changed flake.lock; the `nix` stub fails when its arguments contain
# STUB_NIX_FAIL_ON.
mkdir -p "$work/bin"
nix_log="$work/nix.log"
jj_log="$work/jj.log"
cat >"$work/bin/nix" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$nix_log"
if [[ -n \${STUB_NIX_FAIL_ON-} && "\$*" == *"\$STUB_NIX_FAIL_ON"* ]]; then
	exit 1
fi
EOF
cat >"$work/bin/jj" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$jj_log"
case "\$*" in
"log -r @ --no-graph -T empty") echo true ;;
"diff -r @ --name-only") echo flake.lock ;;
esac
EOF
chmod +x "$work/bin/nix" "$work/bin/jj"
stub_path="$work/bin:$PATH"

# Runs flake-update from the test repository with the stubs first on PATH,
# after emptying their logs.
run_flake_update() {
	: >"$nix_log"
	: >"$jj_log"
	PATH=$stub_path run_app "$repo" flake-update
}

# Prints the steps the stub `nix` ran, in order, on one line: update,
# eval-blueprints, flake-check, and home-build.
nix_steps() {
	local steps=() line
	while IFS= read -r line; do
		case $line in
		"flake update"*) steps+=(update) ;;
		*.#eval-blueprints*) steps+=(eval-blueprints) ;;
		"flake check"*) steps+=(flake-check) ;;
		*.#homeConfigurations.*.activationPackage*) steps+=(home-build) ;;
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
		echo "not ok - $name: expected '$expected', got '$actual'" >&2
		failures=$((failures + 1))
	fi
}

rm "$XDG_CONFIG_HOME/dotfiles/blueprint-id"
run_flake_update
expect "flake-update without a marker names how to bootstrap" 1 "nix run .#switch-home -- --blueprint <blueprint-id>"
expect_equal "flake-update without a marker runs no nix or jj" "" "$(cat "$nix_log" "$jj_log")"

printf '%s\n' "$blueprint_id" >"$XDG_CONFIG_HOME/dotfiles/blueprint-id"
STUB_NIX_FAIL_ON="flake check" run_flake_update
expect "a failing flake check leaves the update uncommitted" 1 "error: nix flake check failed; the dependency update stays uncommitted in @"
expect_equal "a failing flake check stops before the home build" "update eval-blueprints flake-check" "$(nix_steps)"
expect_equal "a failing flake check commits nothing" "" "$(grep '^commit' "$jj_log")"

STUB_NIX_FAIL_ON=homeConfigurations run_flake_update
expect "a failing home build leaves the update uncommitted" 1 "the dependency update stays uncommitted in @"
expect_equal "the home build runs after the flake check" "update eval-blueprints flake-check home-build" "$(nix_steps)"
expect_equal "a failing home build commits nothing" "" "$(grep '^commit' "$jj_log")"

run_flake_update
expect "flake-update commits after every check passes" 0 "Selected blueprint '$blueprint_id' from marker"
expect_equal "flake-update checks in order" "update eval-blueprints flake-check home-build" "$(nix_steps)"
expect_equal "flake-update commits the update last" "commit -m build(nix): update dependencies" "$(tail -n 1 "$jj_log")"

mkdir -p "$work/private"
touch "$work/private/flake.nix"
DOTFILES_PRIVATE_LOCAL="$work/private" run_flake_update
expect_equal "DOTFILES_PRIVATE_LOCAL reaches the flake check" "1" \
	"$(grep -c "^flake check .*--override-input dotfiles-private path:$work/private" "$nix_log")"

if [[ $failures -ne 0 ]]; then
	echo "$failures case(s) failed" >&2
	exit 1
fi
