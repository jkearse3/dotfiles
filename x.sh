#!/usr/bin/env bash

set -e

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

snapshot() {
	jj st >/dev/null 2>&1 || true
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

blueprint_inventory() {
	load_private_override_args
	nix eval --json .#blueprints --accept-flake-config "${PRIVATE_OVERRIDE_ARGS[@]}"
}

configure_blueprint() {
	local blueprint_id="$1"
	local source="$2"
	local inventory="$3"
	local metadata
	if ! metadata="$(jq -ce --arg blueprint_id "$blueprint_id" '.[$blueprint_id] // empty' <<<"$inventory")"; then
		echo "error: unknown blueprint '$blueprint_id'; run './x.sh nix-blueprints' to list canonical IDs" >&2
		exit 1
	fi

	local blueprint_os home_configuration system_configuration
	blueprint_os="$(jq -r .os <<<"$metadata")"
	home_configuration="$(jq -r .homeConfiguration <<<"$metadata")"
	system_configuration="$(jq -r .systemConfiguration <<<"$metadata")"

	case "$blueprint_os" in
	darwin)
		SYSTEM_FLAKE_ATTR=".#darwinConfigurations.${system_configuration}.system"
		;;
	*)
		echo "error: unsupported OS '$blueprint_os' for blueprint '$blueprint_id'" >&2
		exit 1
		;;
	esac

	BLUEPRINT_ID="$blueprint_id"
	BLUEPRINT_SOURCE="$source"
	HOME_FLAKE_ATTR=".#homeConfigurations.${home_configuration}.activationPackage"
	HOME_RESULT_PATH="./result-home-${blueprint_id}"
	SYSTEM_RESULT_PATH="./result-system-${blueprint_id}"
	BLUEPRINT_LOADED=1
	echo "Selected blueprint '$blueprint_id' from $source"
}

require_blueprint() {
	[[ -n $BLUEPRINT_LOADED ]] && return
	[[ -n $BLUEPRINT_ID ]] || read_blueprint_marker

	local inventory
	if ! inventory="$(blueprint_inventory)"; then
		echo "error: unable to load canonical blueprint metadata" >&2
		exit 1
	fi
	configure_blueprint "$BLUEPRINT_ID" "$BLUEPRINT_SOURCE" "$inventory"
}

run_for_blueprint() {
	local fn="$1"
	shift

	if [[ $# -eq 0 ]]; then
		:
	elif [[ $# -eq 2 && $1 == --blueprint && -n $2 ]]; then
		BLUEPRINT_ID="$2"
		BLUEPRINT_SOURCE="--blueprint"
	else
		echo "error: blueprint commands accept only '--blueprint <blueprint-id>'" >&2
		exit 1
	fi

	require_blueprint
	"$fn"
}

require_no_arguments() {
	if [[ $# -ne 0 ]]; then
		echo "error: unexpected arguments: $*" >&2
		exit 1
	fi
}

nix-eval() {
	snapshot
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
	inventory="$(blueprint_inventory)"

	local blueprint
	while IFS= read -r blueprint; do
		configure_blueprint "$blueprint" "canonical inventory" "$inventory"
		nix-eval "$HOME_FLAKE_ATTR"
		nix-eval "$SYSTEM_FLAKE_ATTR"
	done < <(jq -r 'keys[]' <<<"$inventory")
}

cmd:nix-eval-all() {
	require_no_arguments "$@"
	nix-eval-all
}

cmd:nix-blueprints() {
	require_no_arguments "$@"
	local inventory
	inventory="$(blueprint_inventory)"
	jq -r 'keys[]' <<<"$inventory"
}

nix-build() {
	NIX_BUILDER="nix"
	[[ -x ~/.nix-profile/bin/nom ]] && NIX_BUILDER="nom"
	snapshot
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

nix-diff-home() {
	nvd-diff ~/.local/state/nix/profiles/home-manager "$HOME_RESULT_PATH"
}

nix-diff-system() {
	nvd-diff /run/current-system "$SYSTEM_RESULT_PATH"
}

nix-activate-home() {
	echo "Activating home config..."
	"$HOME_RESULT_PATH/activate"
}

nix-activate-system() {
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
	snapshot
	shopt -s nullglob
	local updaters=(packages/*/update.sh)
	shopt -u nullglob
	if [[ ${#updaters[@]} -eq 0 ]]; then
		echo "No package updaters found"
		return
	fi
	for updater in "${updaters[@]}"; do
		echo "Updating $updater..."
		"$updater" --latest "$@"
	done
}

cmd:nix-flake-update() {
	load_private_override_args
	if [[ $(jj log -r '@' --no-graph -T 'if(empty, "true", "false")') != true ]]; then
		jj new
	fi
	nix flake update --accept-flake-config "${PRIVATE_OVERRIDE_ARGS[@]}"
	cmd:nix-package-update "$@"
	local changed_files
	changed_files="$(jj diff -r @ --name-only)"
	if [[ -z $changed_files ]]; then
		echo "dependencies unchanged, skipping eval and commit"
		return
	fi
	nix-eval-all
	desc='build(nix): update dependencies'
	printf '%s\n' "$desc" | commit-message validate
	jj commit -m "$desc"
}

cmd:fmt() {
	require_no_arguments "$@"
	snapshot
	echo "Formatting..."
	load_private_override_args
	nix fmt --accept-flake-config "${PRIVATE_OVERRIDE_ARGS[@]}" -- --no-cache
}

cmd:fmt-check() {
	require_no_arguments "$@"
	snapshot
	echo "Checking formatting..."
	load_private_override_args
	nix fmt --accept-flake-config "${PRIVATE_OVERRIDE_ARGS[@]}" -- --no-cache --fail-on-change
}

cmd:lint() {
	require_no_arguments "$@"
	lint-nix
	lint-shell
	lint-python
}

lint-nix() {
	snapshot
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
	require_no_arguments "$@"
	lint-nix
}

lint-shell() {
	snapshot
	local files=()
	mapfile -d '' -t files < <(git ls-files -z --cached --others --exclude-standard '*.sh')
	if [[ ${#files[@]} -eq 0 ]]; then
		echo "No shell scripts found"
		return 0
	fi
	echo "Linting shell scripts..."
	shellcheck "${files[@]}"
}

cmd:lint-shell() {
	require_no_arguments "$@"
	lint-shell
}

lint-python() {
	snapshot
	echo "Checking Python types..."
	basedpyright --project pyrightconfig.json --warnings
}

cmd:lint-python() {
	require_no_arguments "$@"
	lint-python
}

cmd:python-check() {
	require_no_arguments "$@"
	lint-python
}

usage() {
	echo "usage: $0 <command> [arguments]" >&2
	echo "" >&2
	echo "commands:" >&2
	declare -F | sed -n 's/.*cmd://p' | sort | sed 's/^/  /' >&2
}

main() {
	if [[ -z ${1:-} ]]; then
		usage
		exit 1
	fi
	local command="$1"
	local command_fn="cmd:$command"
	shift

	if declare -f "$command_fn" >/dev/null 2>&1; then
		"$command_fn" "$@"
	else
		echo "error: unknown command '$command'" >&2
		usage
		exit 1
	fi
}

main "$@"
