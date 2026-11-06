#!/usr/bin/env bash

# The commands behind this repository's flake apps: `nix run .#<command> --
# [options]` runs `dotfiles-apps <command> [options]` from the repository root.
# build-home, switch-home, build-system, and switch-system build or activate the
# selected blueprint; package-update and flake-update update dependencies.
# `package.nix` prepends `blueprint_output`, generated from the flake's
# `blueprints` inventory at build time, so blueprint selection needs no Nix
# evaluation.

# Prints the usage of `command` to standard output.
usage() {
	local command=$1

	case $command in
	build-home | switch-home)
		cat <<EOF
usage: nix run .#$command -- [--blueprint <blueprint-id>] [--locked]

  --blueprint <blueprint-id>  select a blueprint instead of reading the
                              dotfiles/blueprint-id marker
  --locked                    use store-backed home sources instead of editable ones
  --help                      print this usage
EOF
		;;
	build-system | switch-system)
		cat <<EOF
usage: nix run .#$command -- [--blueprint <blueprint-id>]

  --blueprint <blueprint-id>  select a blueprint instead of reading the
                              dotfiles/blueprint-id marker
  --help                      print this usage
EOF
		;;
	package-update)
		cat <<EOF
usage: nix run .#package-update -- [--dry-run]

  --dry-run                   print the new pins without editing files
  --help                      print this usage
EOF
		;;
	flake-update)
		cat <<EOF
usage: nix run .#flake-update

Reads the dotfiles/blueprint-id marker and, after evaluating every blueprint
and running \`nix flake check\`, builds that blueprint's home configuration
before committing the update.

  --help                      print this usage
EOF
		;;
	*)
		echo "usage: nix run .#<build-home|switch-home|build-system|switch-system|package-update|flake-update> -- [options]"
		;;
	esac
}

# Reports invalid arguments and exits 2 with the usage on standard error.
fail_usage() {
	local command=$1
	local message=$2

	echo "error: $message" >&2
	usage "$command" >&2
	exit 2
}

# Succeeds when `command` accepts `option`.
accepts_option() {
	case $1:$2 in
	*:--help | *-home:--blueprint | *-home:--locked | *-system:--blueprint | package-update:--dry-run) ;;
	*) return 1 ;;
	esac
}

# Sets `private_override` to the arguments that point every Nix and nh call at a
# local dotfiles-private checkout when DOTFILES_PRIVATE_LOCAL is set: `1`,
# `true`, or `yes` select `$HOME/dotfiles-private`, any other value is the
# checkout path. Leaves it empty when the variable is unset or empty, and exits
# 1 when the path holds no `flake.nix`.
set_private_override() {
	private_override=()
	local value=${DOTFILES_PRIVATE_LOCAL-}
	[[ -n $value ]] || return 0

	local path=$value
	case $value in
	1 | true | yes) path="$HOME/dotfiles-private" ;;
	esac
	if [[ ! -f $path/flake.nix ]]; then
		echo "error: DOTFILES_PRIVATE_LOCAL does not identify a flake checkout: $path" >&2
		exit 1
	fi
	private_override=(--override-input dotfiles-private "path:$path")
}

# Sets `output_name` to the home or system configuration name of the selected
# blueprint: `blueprint_id` when given, as from `--blueprint`, otherwise the ID
# in the `dotfiles/blueprint-id` marker under XDG_CONFIG_HOME (default
# `$HOME/.config`). `kind` is `home` or `system`. Prints the selected ID and its
# source, and exits 1 when no ID is given and the marker is missing, or when the
# ID names no blueprint.
select_blueprint() {
	local kind=$1
	local blueprint_id=$2

	local blueprint_source="--blueprint"
	if [[ -z $blueprint_id ]]; then
		local marker="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/blueprint-id"
		if [[ ! -f $marker ]]; then
			echo "error: no blueprint selected; run 'nix eval .#blueprints --apply builtins.attrNames', then bootstrap with 'nix run .#switch-home -- --blueprint <blueprint-id>'" >&2
			exit 1
		fi
		blueprint_id="$(<"$marker")"
		blueprint_source="marker $marker"
	fi

	if ! output_name="$(blueprint_output "$kind" "$blueprint_id")"; then
		echo "error: unknown blueprint '$blueprint_id' from $blueprint_source; run 'nix eval .#blueprints --apply builtins.attrNames' to list canonical IDs" >&2
		exit 1
	fi
	echo "Selected blueprint '$blueprint_id' from $blueprint_source"
}

# Prints the nh `--diff` mode that compares a build with the configuration in
# use: `always` when its profile exists, otherwise `never` with a warning, as on
# a machine that has not activated it yet. nh's default `auto` compares only
# when the configuration name matches the hostname, which blueprint IDs
# deliberately do not.
nh_diff_mode() {
	local current_profile=$1
	if [[ -e $current_profile ]]; then
		echo always
	else
		echo "warning: $current_profile does not exist, skipping diff" >&2
		echo never
	fi
}

# Runs `nh home <build|switch>` on a Home Manager configuration. nh keeps its
# result link in a temporary directory and, for switch, activates without
# elevation. Locked mode selects store-backed home sources through
# DOTFILES_HOME_LOCKED, which evaluation reads only with `--impure`.
nh_home() {
	local action=$1
	local home_configuration_name=$2
	local is_locked=$3

	local locked_args=()
	if [[ -n $is_locked ]]; then
		export DOTFILES_HOME_LOCKED=1
		locked_args=(--impure)
	else
		unset DOTFILES_HOME_LOCKED
	fi

	local diff_mode
	diff_mode="$(nh_diff_mode "$HOME/.local/state/nix/profiles/home-manager")"

	nh home "$action" . -c "$home_configuration_name" --diff "$diff_mode" --show-trace --accept-flake-config "${private_override[@]}" "${locked_args[@]}"
}

# Runs `nh darwin <build|switch>` on a nix-darwin configuration. The app itself
# never runs as root; nh elevates only to record the system profile and
# activate on switch.
nh_darwin() {
	local action=$1
	local darwin_configuration_name=$2

	local diff_mode
	diff_mode="$(nh_diff_mode /run/current-system)"

	nh darwin "$action" . -H "$darwin_configuration_name" --diff "$diff_mode" --show-trace --accept-flake-config "${private_override[@]}"
}

# Runs every package updater, `packages/*/update.sh --latest`, which pins its
# package to the latest upstream release. With `is_dry_run` set, the updaters
# also get `--dry-run` and print the new pins without editing files. Exits with
# the status of the first updater that fails.
package_update() {
	local is_dry_run=$1

	local updater_args=(--latest)
	if [[ -n $is_dry_run ]]; then
		updater_args+=(--dry-run)
	fi

	shopt -s nullglob
	local updaters=(packages/*/update.sh)
	shopt -u nullglob
	if [[ ${#updaters[@]} -eq 0 ]]; then
		echo "No package updaters found"
		return
	fi
	local updater
	for updater in "${updaters[@]}"; do
		echo "Updating $updater..."
		"$updater" "${updater_args[@]}"
	done
}

# Runs `nix` with the remaining arguments as one check of an uncommitted
# dependency update. When it fails, reports which check failed and that the
# update stays in `@` for the fix, and exits 1.
check_dependency_update() {
	local check_name=$1
	shift

	if ! nix "$@"; then
		echo "error: $check_name failed; the dependency update stays uncommitted in @ so the fix can land in the same change" >&2
		exit 1
	fi
}

# Updates the flake inputs and every package pin in a jj change of their own,
# then commits it as "build(nix): update dependencies" once every blueprint
# still evaluates, `nix flake check` passes, and the Home Manager configuration
# `home_configuration_name` builds. Starts a new change first when the working
# copy is not empty, and commits nothing when no dependency changed. When a
# check fails, exits 1 and leaves the update uncommitted in `@`. `jj` comes from
# the user's PATH.
flake_update() {
	local home_configuration_name=$1

	local is_working_copy_empty
	is_working_copy_empty="$(jj log -r @ --no-graph -T empty)"
	if [[ $is_working_copy_empty != true ]]; then
		jj new
	fi

	nix flake update --accept-flake-config "${private_override[@]}"
	package_update ""

	local changed_files
	changed_files="$(jj diff -r @ --name-only)"
	if [[ -z $changed_files ]]; then
		echo "dependencies unchanged, skipping evaluation"
		return
	fi

	check_dependency_update "nix build .#eval-blueprints" \
		build --no-link --accept-flake-config "${private_override[@]}" .#eval-blueprints
	check_dependency_update "nix flake check" \
		flake check --accept-flake-config "${private_override[@]}"
	check_dependency_update "building home configuration '$home_configuration_name'" \
		build --no-link --accept-flake-config "${private_override[@]}" ".#homeConfigurations.\"$home_configuration_name\".activationPackage"

	jj commit -m "build(nix): update dependencies"
}

# Runs `command`: build-home, switch-home, build-system, or switch-system on the
# blueprint selected by `--blueprint` or the marker, or package-update or
# flake-update, which builds the home configuration of the blueprint the marker
# selects. Argument errors exit 2 before anything else; the working-directory
# guard, DOTFILES_PRIVATE_LOCAL, and blueprint selection exit 1 before any Nix,
# nh, or jj call.
main() {
	local command=${1-}
	shift || true
	case $command in
	build-home | switch-home | build-system | switch-system | package-update | flake-update) ;;
	*) fail_usage "$command" "unknown command '$command'" ;;
	esac

	local blueprint_id="" is_locked="" is_dry_run=""
	while [[ $# -gt 0 ]]; do
		accepts_option "$command" "$1" || fail_usage "$command" "$command does not accept '$1'"
		case $1 in
		--help)
			usage "$command"
			exit 0
			;;
		--blueprint)
			[[ $# -ge 2 && -n $2 ]] || fail_usage "$command" "--blueprint requires a blueprint ID"
			blueprint_id=$2
			shift
			;;
		--locked) is_locked=1 ;;
		--dry-run) is_dry_run=1 ;;
		esac
		shift
	done

	# Every command works on `.`: nh builds it, and the built-in blueprint
	# inventory matches it only when `.` is this repository.
	if [[ ! -f flake.nix || ! -f flake/blueprints/default.nix ]]; then
		echo "error: $command must run from the dotfiles repository root" >&2
		exit 1
	fi

	if [[ $command == package-update ]]; then
		package_update "$is_dry_run"
		return
	fi

	local private_override
	set_private_override

	local output_name
	if [[ $command == flake-update ]]; then
		select_blueprint home ""
		flake_update "$output_name"
		return
	fi

	select_blueprint "${command#*-}" "$blueprint_id"

	case $command in
	*-home) nh_home "${command%-home}" "$output_name" "$is_locked" ;;
	*-system) nh_darwin "${command%-system}" "$output_name" ;;
	esac
}

main "$@"
