#!/usr/bin/env bash

# The commands behind this repository's flake apps: `nix run .#<command> --
# [options]` runs `dotfiles-apps <command> [options]` from the repository root.
# build-home, switch-home, build-system, and switch-system build or activate the
# selected blueprint; package-update and flake-update, whose implementation
# `flake-update.sh` holds, update dependencies.
# switch-home and switch-system refuse to run from a linked Git worktree or
# secondary jj workspace unless given `--allow-worktree`.
# `package.nix` prepends `blueprint_output`, generated from the flake's
# `blueprints` inventory at build time, so blueprint selection needs no Nix
# evaluation.

# Prints the usage of `command` to standard output.
usage() {
	local command=$1

	case $command in
	build-home | build-system)
		cat <<EOF
usage: nix run .#$command -- [--blueprint <blueprint-id>]

  --blueprint <blueprint-id>  select a blueprint instead of reading the
                              dotfiles/blueprint-id marker
  --help                      print this usage
EOF
		;;
	switch-home | switch-system)
		cat <<EOF
usage: nix run .#$command -- [--blueprint <blueprint-id>] [--allow-worktree]

  --blueprint <blueprint-id>  select a blueprint instead of reading the
                              dotfiles/blueprint-id marker
  --allow-worktree            switch from a linked Git worktree or secondary
                              jj workspace instead of the main checkout
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

Updates flake.lock and the package pins in a jj change of their own. Once
every blueprint evaluates, \`nix flake check\` passes, and the home and system
configurations of the blueprint in the dotfiles/blueprint-id marker build, it
commits the change with a description listing the inputs, pins, and package
versions that changed. When a check fails, the update stays in @; rerunning
resumes it, rerunning the checks without updating again.

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
	*:--help | *-home:--blueprint | *-system:--blueprint | package-update:--dry-run) ;;
	switch-home:--allow-worktree | switch-system:--allow-worktree) ;;
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
# blueprint and `selected_blueprint_id` to its ID: `blueprint_id` when given, as from `--blueprint`, otherwise the ID
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
	selected_blueprint_id=$blueprint_id
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
# elevation.
nh_home() {
	local action=$1
	local home_configuration_name=$2

	local diff_mode
	diff_mode="$(nh_diff_mode "$HOME/.local/state/nix/profiles/home-manager")"

	nh home "$action" . -c "$home_configuration_name" --diff "$diff_mode" --show-trace --accept-flake-config "${private_override[@]}"
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
		"$updater" "${updater_args[@]}" || return
	done
}

# Returns when `.` is the main checkout of its Git repository, where git-dir
# and the common Git directory coincide. From a linked Git worktree or a
# secondary colocated jj workspace, whose files activation would install for
# every session, prints an error naming the main checkout and exits 1 on behalf
# of `command`. Also exits 1 when git cannot find the Git directory or list the
# worktrees, so an unknown checkout never switches.
require_main_checkout() {
	local command=$1

	local git_dirs="" git_dir="" common_dir=""
	if git_dirs="$(git rev-parse --path-format=absolute --git-dir --git-common-dir)"; then
		{
			read -r git_dir
			read -r common_dir
		} <<<"$git_dirs" || true
	fi
	if [[ -z $git_dir || -z $common_dir ]]; then
		echo "error: $command cannot tell whether $PWD is the main checkout because git could not find its Git directory; run it from the main checkout, or pass --allow-worktree to switch from here anyway" >&2
		exit 1
	fi
	[[ $git_dir == "$common_dir" ]] && return 0

	# The first entry of the porcelain worktree list is the main checkout.
	local worktree_list="" main_checkout=""
	if worktree_list="$(git worktree list --porcelain)"; then
		main_checkout=${worktree_list%%$'\n'*}
	fi
	if [[ $main_checkout != "worktree "?* ]]; then
		echo "error: $command cannot tell whether $PWD is the main checkout because git could not list its worktrees; run it from the main checkout, or pass --allow-worktree to switch from here anyway" >&2
		exit 1
	fi
	echo "error: $command must run from the main checkout ${main_checkout#worktree }, not from a linked Git worktree or secondary jj workspace; run it there, or pass --allow-worktree to switch from this checkout" >&2
	exit 1
}

# Runs `command`: build-home, switch-home, build-system, or switch-system on the
# blueprint selected by `--blueprint` or the marker, or package-update or
# flake-update, which builds the home and system configurations of the
# blueprint the marker selects. Argument errors exit 2 before anything else; the
# working-directory guards (the repository root, and for switch apps the main
# checkout unless `--allow-worktree` is given), DOTFILES_PRIVATE_LOCAL, and
# blueprint selection exit 1 before any Nix, nh, or jj call.
main() {
	local command=${1-}
	shift || true
	case $command in
	build-home | switch-home | build-system | switch-system | package-update | flake-update) ;;
	*) fail_usage "$command" "unknown command '$command'" ;;
	esac

	local blueprint_id="" is_dry_run="" allows_worktree=""
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
		--dry-run) is_dry_run=1 ;;
		--allow-worktree) allows_worktree=1 ;;
		esac
		shift
	done

	# Every command works on `.`: nh builds it, and the built-in blueprint
	# inventory matches it only when `.` is this repository.
	if [[ ! -f flake.nix || ! -f flake/blueprints/default.nix ]]; then
		echo "error: $command must run from the dotfiles repository root" >&2
		exit 1
	fi
	if [[ $command == switch-* && -z $allows_worktree ]]; then
		require_main_checkout "$command"
	fi

	if [[ $command == package-update ]]; then
		package_update "$is_dry_run"
		return
	fi

	local private_override
	set_private_override

	local output_name selected_blueprint_id
	if [[ $command == flake-update ]]; then
		select_blueprint home ""
		flake_update "$selected_blueprint_id" "$output_name" "$(blueprint_output system "$selected_blueprint_id")"
		return
	fi

	select_blueprint "${command#*-}" "$blueprint_id"

	case $command in
	*-home) nh_home "${command%-home}" "$output_name" ;;
	*-system) nh_darwin "${command%-system}" "$output_name" ;;
	esac
}

main "$@"
