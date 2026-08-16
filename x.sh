#!/usr/bin/env bash

if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4))); then
	echo "error: x.sh requires Bash 4.4 or newer; rerun as 'nix develop --command ./x.sh <command> [arguments]'" >&2
	exit 1
fi

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

BLUEPRINT_ID=""
BLUEPRINT_SOURCE=""
BLUEPRINT_LOADED=""
HOME_FLAKE_ATTR=""
SYSTEM_FLAKE_ATTR=""
HOME_RESULT_PATH=""
SYSTEM_RESULT_PATH=""
PRIVATE_OVERRIDE_ARGS=()

ssh_agent_socket_is_responsive() {
	local socket_path=$1
	[[ -S $socket_path ]] || return 1

	local status=0
	SSH_AUTH_SOCK="$socket_path" ssh-add -l >/dev/null 2>&1 || status=$?
	[[ $status -lt 2 ]]
}

select_1password_ssh_agent_socket() {
	local platform=$1
	local normalized_socket=$2
	local darwin_socket=$3

	if ssh_agent_socket_is_responsive "$normalized_socket"; then
		printf '%s\n' "$normalized_socket"
		return
	fi

	if [[ $platform == Darwin ]] && ssh_agent_socket_is_responsive "$darwin_socket"; then
		printf '%s\n' "$darwin_socket"
	fi
}

configure_1password_ssh_agent() {
	local normalized_socket="$HOME/.1password/agent.sock"
	# Home Manager creates the normalized symlink after the first activation.
	local darwin_socket="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
	local selected_socket
	selected_socket="$(select_1password_ssh_agent_socket "$(uname -s)" "$normalized_socket" "$darwin_socket")"

	if [[ -n $selected_socket ]]; then
		export SSH_AUTH_SOCK="$selected_socket"
	fi
}

snapshot_jj_working_copy() {
	command -v jj >/dev/null 2>&1 || return 0
	jj status >/dev/null
}

load_private_override_args() {
	local val="${DOTFILES_PRIVATE_LOCAL-}"
	PRIVATE_OVERRIDE_ARGS=()
	[[ -z $val ]] && return
	local path
	case $val in
	1 | true | yes) path="$HOME/dotfiles-private" ;;
	*) path="$val" ;;
	esac
	if [[ ! -f $path/flake.nix ]]; then
		echo "error: DOTFILES_PRIVATE_LOCAL does not identify a flake checkout: $path" >&2
		exit 1
	fi
	PRIVATE_OVERRIDE_ARGS=(--override-input dotfiles-private "path:$path")
}

read_blueprint_marker() {
	# Home Manager writes this marker during activation; an explicit
	# `--blueprint` selection bypasses it for first-time bootstrap.
	local marker="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/blueprint-id"
	if [[ ! -f $marker ]]; then
		echo "error: no blueprint selected; run './x.sh nix-blueprints', then bootstrap with './x.sh nix-switch-home --blueprint <blueprint-id>'" >&2
		exit 1
	fi

	local contents marker_bytes
	contents="$(<"$marker")"
	marker_bytes="$(wc -c <"$marker")"
	if [[ -z $contents ||
		$marker_bytes -ne $((${#contents} + 1)) ||
		$contents == *$'\n'* ||
		$contents != "${contents#"${contents%%[![:space:]]*}"}" ||
		$contents != "${contents%"${contents##*[![:space:]]}"}" ]]; then
		echo "error: malformed blueprint marker $marker; run './x.sh nix-blueprints', then override with '--blueprint <blueprint-id>'" >&2
		exit 1
	fi

	BLUEPRINT_ID="$contents"
	BLUEPRINT_SOURCE="marker $marker"
}

load_blueprint_inventory() {
	# The public inventory is the shell-to-Nix contract; shell commands do not
	# duplicate authored blueprint identities or output naming rules.
	load_private_override_args

	local inventory
	if ! inventory="$(nix eval --json .#blueprints --accept-flake-config "${PRIVATE_OVERRIDE_ARGS[@]}")"; then
		echo "error: unable to evaluate canonical blueprint metadata" >&2
		return 1
	fi

	printf '%s\n' "$inventory"
}

configure_blueprint_selection() {
	local blueprint_id="$1"
	local source="$2"
	local inventory="$3"
	local metadata
	if ! metadata="$(jq -ce --arg blueprint_id "$blueprint_id" '.[$blueprint_id] // empty' <<<"$inventory")"; then
		echo "error: unknown blueprint '$blueprint_id'; run './x.sh nix-blueprints' to list canonical IDs" >&2
		exit 1
	fi

	local blueprint_os home_configuration_name darwin_configuration_name
	blueprint_os="$(jq -r .os <<<"$metadata")"
	home_configuration_name="$(jq -r .homeConfigurationName <<<"$metadata")"
	darwin_configuration_name="$(jq -r .darwinConfigurationName <<<"$metadata")"

	case "$blueprint_os" in
	darwin)
		SYSTEM_FLAKE_ATTR=".#darwinConfigurations.${darwin_configuration_name}.system"
		;;
	*)
		echo "error: unsupported OS '$blueprint_os' for blueprint '$blueprint_id'" >&2
		exit 1
		;;
	esac

	BLUEPRINT_ID="$blueprint_id"
	BLUEPRINT_SOURCE="$source"
	HOME_FLAKE_ATTR=".#homeConfigurations.${home_configuration_name}.activationPackage"
	HOME_RESULT_PATH="./result-home-${blueprint_id}"
	SYSTEM_RESULT_PATH="./result-system-${blueprint_id}"
	BLUEPRINT_LOADED=1
	echo "Selected blueprint '$blueprint_id' from $source"
}

require_blueprint() {
	[[ -n $BLUEPRINT_LOADED ]] && return
	[[ -n $BLUEPRINT_ID ]] || read_blueprint_marker

	local inventory
	if ! inventory="$(load_blueprint_inventory)"; then
		echo "error: unable to load canonical blueprint metadata" >&2
		exit 1
	fi
	configure_blueprint_selection "$BLUEPRINT_ID" "$BLUEPRINT_SOURCE" "$inventory"
}

run_for_blueprint() {
	local fn="$1"
	shift

	if [[ $# -eq 0 ]]; then
		:
	else
		BLUEPRINT_ID="$2"
		BLUEPRINT_SOURCE="--blueprint"
	fi

	require_blueprint
	"$fn"
}

nix-eval() {
	echo "Evaluating $1..."
	load_private_override_args
	nix eval --raw "$1" --accept-flake-config "${PRIVATE_OVERRIDE_ARGS[@]}" "${@:2}"
	echo ""
}

nix-eval-home() {
	local extra=()
	[[ -n ${DOTFILES_HOME_LOCKED:-} ]] && extra+=(--impure)
	nix-eval "$HOME_FLAKE_ATTR" "${extra[@]}"
}

nix-eval-home-locked() {
	DOTFILES_HOME_LOCKED=1 nix-eval-home
}

nix-eval-system() {
	nix-eval "$SYSTEM_FLAKE_ATTR"
}

cmd:nix-eval-home() {
	run_for_blueprint nix-eval-home "$@"
}

cmd:nix-eval-home-locked() {
	run_for_blueprint nix-eval-home-locked "$@"
}

cmd:nix-eval-system() {
	run_for_blueprint nix-eval-system "$@"
}

nix-eval-all() {
	local inventory
	inventory="$(load_blueprint_inventory)"

	local blueprint blueprints
	if ! blueprints="$(jq -r 'keys[]' <<<"$inventory")"; then
		echo "error: unable to read canonical blueprint IDs" >&2
		return 1
	fi
	while IFS= read -r blueprint; do
		configure_blueprint_selection "$blueprint" "canonical inventory" "$inventory"
		nix-eval "$HOME_FLAKE_ATTR"
		nix-eval "$SYSTEM_FLAKE_ATTR"
	done <<<"$blueprints"
}

cmd:nix-eval-all() {
	nix-eval-all
}

cmd:nix-blueprints() {
	local inventory
	inventory="$(load_blueprint_inventory)"
	jq -r 'keys[]' <<<"$inventory"
}

nix-build() {
	NIX_BUILDER="nix"
	[[ -x ~/.nix-profile/bin/nom ]] && NIX_BUILDER="nom"
	echo "Building $1..."
	load_private_override_args
	$NIX_BUILDER build "$1" -o "$2" --show-trace --accept-flake-config "${PRIVATE_OVERRIDE_ARGS[@]}" "${@:3}"
}

nix-build-home() {
	local extra=()
	[[ -n ${DOTFILES_HOME_LOCKED:-} ]] && extra+=(--impure)
	nix-build "$HOME_FLAKE_ATTR" "$HOME_RESULT_PATH" "${extra[@]}"
}

nix-build-home-locked() {
	DOTFILES_HOME_LOCKED=1 nix-build-home
}

nix-build-system() {
	nix-build "$SYSTEM_FLAKE_ATTR" "$SYSTEM_RESULT_PATH"
}

cmd:nix-build-home() {
	run_for_blueprint nix-build-home "$@"
}

cmd:nix-build-home-locked() {
	run_for_blueprint nix-build-home-locked "$@"
}

cmd:nix-build-system() {
	run_for_blueprint nix-build-system "$@"
}

nvd-diff() {
	command -v nvd &>/dev/null || {
		echo "warning: nvd not installed, skipping diff" >&2
		return
	}
	[[ -e $1 ]] || {
		echo "warning: $1 does not exist, skipping diff" >&2
		return
	}
	echo "Diffing..."
	nvd diff "$1" "$2"
}

require_result() {
	local result_path=$1
	local build_command=$2
	local executable=${3:-}
	if [[ ! -e $result_path ]]; then
		echo "error: required result '$result_path' is missing; run '$build_command'" >&2
		return 1
	fi
	if [[ -n $executable && ! -x $result_path/$executable ]]; then
		echo "error: required executable '$result_path/$executable' is missing; run '$build_command'" >&2
		return 1
	fi
}

nix-diff-home() {
	require_result "$HOME_RESULT_PATH" "./x.sh nix-build-home --blueprint $BLUEPRINT_ID" || return
	nvd-diff ~/.local/state/nix/profiles/home-manager "$HOME_RESULT_PATH"
}

nix-diff-system() {
	require_result "$SYSTEM_RESULT_PATH" "./x.sh nix-build-system --blueprint $BLUEPRINT_ID" || return
	nvd-diff /run/current-system "$SYSTEM_RESULT_PATH"
}

nix-activate-home() {
	require_result "$HOME_RESULT_PATH" "./x.sh nix-build-home --blueprint $BLUEPRINT_ID" activate || return
	echo "Activating home config..."
	"$HOME_RESULT_PATH/activate"
}

nix-activate-system() {
	require_result "$SYSTEM_RESULT_PATH" "./x.sh nix-build-system --blueprint $BLUEPRINT_ID" activate || return
	echo "Activating system config (requires sudo)..."
	sudo "$SYSTEM_RESULT_PATH/activate"
}

nix-switch-home() {
	nix-build-home
	nix-diff-home
	nix-activate-home
}

nix-switch-home-locked() {
	DOTFILES_HOME_LOCKED=1 nix-switch-home
}

nix-switch-system() {
	nix-build-system
	nix-diff-system
	nix-activate-system
}

cmd:nix-diff-home() {
	run_for_blueprint nix-diff-home "$@"
}

cmd:nix-diff-system() {
	run_for_blueprint nix-diff-system "$@"
}

cmd:nix-activate-home() {
	run_for_blueprint nix-activate-home "$@"
}

cmd:nix-activate-system() {
	run_for_blueprint nix-activate-system "$@"
}

cmd:nix-switch-home() {
	run_for_blueprint nix-switch-home "$@"
}

cmd:nix-switch-home-locked() {
	run_for_blueprint nix-switch-home-locked "$@"
}

cmd:nix-switch-system() {
	run_for_blueprint nix-switch-system "$@"
}

cmd:nix-package-update() {
	local updater_args=(--latest)
	if [[ $# -eq 1 ]]; then
		updater_args+=(--dry-run)
	fi

	shopt -s nullglob
	local updaters=(packages/*/update.sh)
	shopt -u nullglob
	if [[ ${#updaters[@]} -eq 0 ]]; then
		echo "No package updaters found"
		return
	fi
	for updater in "${updaters[@]}"; do
		echo "Updating $updater..."
		"$updater" "${updater_args[@]}"
	done
}

cmd:nix-flake-update() {
	load_private_override_args
	local working_copy_empty
	if ! working_copy_empty="$(jj log -r '@' --no-graph -T 'if(empty, "true", "false")')"; then
		echo "error: unable to inspect the jj working copy before updating dependencies" >&2
		return 1
	fi
	if [[ $working_copy_empty != true ]]; then
		jj new
	fi
	nix flake update --accept-flake-config "${PRIVATE_OVERRIDE_ARGS[@]}"
	cmd:nix-package-update "$@"
	local changed_files
	if ! changed_files="$(jj diff -r @ --name-only)"; then
		echo "error: unable to inspect dependency changes" >&2
		return 1
	fi
	if [[ -z $changed_files ]]; then
		echo "dependencies unchanged, skipping evaluation"
		return
	fi
	nix-eval-all
	jj commit -m "build(nix): update dependencies"
}

cmd:fmt() {
	echo "Formatting..."
	load_private_override_args
	nix fmt --accept-flake-config "${PRIVATE_OVERRIDE_ARGS[@]}" -- --no-cache
}

cmd:fmt-check() {
	echo "Checking formatting..."
	load_private_override_args
	nix build .#checks.aarch64-darwin.treefmt --no-link --no-write-lock-file --accept-flake-config "${PRIVATE_OVERRIDE_ARGS[@]}"
}

cmd:lint() {
	lint-nix
	lint-shell
	lint-python
}

lint-nix() {
	local files=()
	local existing_files=()
	local file_list
	file_list="$(mktemp)"
	if ! git ls-files -z --cached --others --exclude-standard '*.nix' >"$file_list"; then
		rm -f "$file_list"
		return 1
	fi
	mapfile -d '' -t files <"$file_list"
	rm -f "$file_list"
	for file in "${files[@]}"; do
		[[ -f $file ]] && existing_files+=("$file")
	done
	files=("${existing_files[@]}")
	if [[ ${#files[@]} -eq 0 ]]; then
		echo "No Nix files found"
		return 0
	fi
	echo "Linting Nix files..."
	statix check .
	deadnix --fail "${files[@]}"
}

cmd:lint-nix() {
	lint-nix
}

lint-shell() {
	local files=()
	local existing_files=()
	local file_list
	file_list="$(mktemp)"
	if ! git ls-files -z --cached '*.sh' '*.bash' >"$file_list"; then
		rm -f "$file_list"
		return 1
	fi
	mapfile -d '' -t files <"$file_list"
	rm -f "$file_list"
	for file in "${files[@]}"; do
		[[ -f $file ]] && existing_files+=("$file")
	done
	files=("${existing_files[@]}")
	if [[ ${#files[@]} -eq 0 ]]; then
		echo "No shell scripts found"
		return 0
	fi
	echo "Linting shell scripts..."
	shellcheck "${files[@]}"
}

cmd:lint-shell() {
	lint-shell
}

lint-python() {
	echo "Checking Python types..."
	basedpyright --project pyrightconfig.json --warnings
}

cmd:lint-python() {
	lint-python
}

cmd:python-check() {
	lint-python
}

validate_command_arguments() {
	local command=$1
	shift

	case $command in
	nix-activate-home | nix-activate-system | nix-build-home | nix-build-home-locked | nix-build-system | nix-diff-home | nix-diff-system | nix-eval-home | nix-eval-home-locked | nix-eval-system | nix-switch-home | nix-switch-home-locked | nix-switch-system)
		[[ $# -eq 0 || ($# -eq 2 && $1 == --blueprint && -n $2) ]] || return 2
		;;
	nix-package-update)
		[[ $# -eq 0 || ($# -eq 1 && $1 == --dry-run) ]] || return 2
		;;
	*)
		[[ $# -eq 0 ]] || return 2
		;;
	esac
}

usage() {
	cat >&2 <<EOF
usage: $0 <command> [arguments]

Blueprint commands accept optional '--blueprint <blueprint-id>'.
nix-package-update accepts optional '--dry-run'.
nix-flake-update and fmt modify the working copy.

commands:
EOF
	declare -F | sed -n 's/.*cmd://p' | sort | sed 's/^/  /' >&2
}

main() {
	if [[ -z ${1:-} ]]; then
		usage
		exit 2
	fi
	local command="$1"
	local command_fn="cmd:$command"
	shift

	if declare -f "$command_fn" >/dev/null 2>&1; then
		if ! validate_command_arguments "$command" "$@"; then
			echo "error: invalid arguments for '$command': $*" >&2
			usage
			return 2
		fi
		configure_1password_ssh_agent
		snapshot_jj_working_copy || return
		"$command_fn" "$@"
	else
		echo "error: unknown command '$command'" >&2
		usage
		exit 2
	fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	main "$@"
fi
