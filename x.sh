#!/usr/bin/env bash

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

HOST="$(hostname -s)"

HOST_OS=$(nix eval --raw ".#hostOs.${HOST}") || {
	echo "error: no hostOs entry for ${HOST}" >&2
	exit 1
}

case "$HOST_OS" in
darwin)
	SYSTEM_NAMESPACE="darwinConfigurations"
	SYSTEM_BUILD_ATTR="system"
	SYSTEM_ACTIVATE=(./result-system/activate)
	;;
nixos)
	SYSTEM_NAMESPACE="nixosConfigurations"
	SYSTEM_BUILD_ATTR="config.system.build.toplevel"
	SYSTEM_ACTIVATE=(./result-system/bin/switch-to-configuration switch)
	;;
*)
	echo "error: unhandled hostOs: $HOST_OS" >&2
	exit 1
	;;
esac

SYSTEM_DERIVATION=".#${SYSTEM_NAMESPACE}.${HOST}.${SYSTEM_BUILD_ATTR}"
HOME_ACTIVATION_PACKAGE=".#homeConfigurations.${USER}@${HOST}.activationPackage"

snapshot() {
	jj st >/dev/null 2>&1 || true
}

private_override_args() {
	local val="${DOTFILES_PRIVATE_LOCAL-}"
	[[ -z $val ]] && return 0
	local path
	case $val in
	1 | true | yes) path="$HOME/dotfiles-private" ;;
	*) path="$val" ;;
	esac
	[[ -f $path/flake.nix ]] || return 0
	printf '%s\n' --override-input dotfiles-private "path:$path"
}

nix-eval() {
	snapshot
	echo "Evaluating $1..."
	local override=()
	mapfile -t override < <(private_override_args)
	nix eval --raw "$1" --accept-flake-config "${override[@]}" "${@:2}"
	echo ""
}

cmd:nix-eval-home() {
	local extra=()
	[[ -n ${DOTFILES_HOME_LOCKED:-} ]] && extra+=(--impure)
	nix-eval "$HOME_ACTIVATION_PACKAGE" "${extra[@]}"
}

cmd:nix-eval-home-locked() {
	DOTFILES_HOME_LOCKED=1 cmd:nix-eval-home
}

cmd:nix-eval-system() {
	nix-eval "$SYSTEM_DERIVATION"
}

nix-build() {
	NIX_BUILDER="nix"
	[[ -x ~/.nix-profile/bin/nom ]] && NIX_BUILDER="nom"
	snapshot
	echo "Building $1..."
	local override=()
	mapfile -t override < <(private_override_args)
	$NIX_BUILDER build "$1" -o "$2" --show-trace --accept-flake-config "${override[@]}" "${@:3}"
}

cmd:nix-build-home() {
	local extra=()
	[[ -n ${DOTFILES_HOME_LOCKED:-} ]] && extra+=(--impure)
	nix-build "$HOME_ACTIVATION_PACKAGE" ./result-home "${extra[@]}"
}

cmd:nix-build-home-locked() {
	DOTFILES_HOME_LOCKED=1 cmd:nix-build-home
}

cmd:nix-build-system() {
	nix-build "$SYSTEM_DERIVATION" ./result-system
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

cmd:nix-diff-home() {
	nvd-diff ~/.local/state/nix/profiles/home-manager ./result-home
}

cmd:nix-diff-system() {
	nvd-diff /run/current-system ./result-system
}

cmd:nix-activate-home() {
	echo "Activating home config..."
	./result-home/activate
}

cmd:nix-activate-system() {
	echo "Activating system config (requires sudo)..."
	sudo "${SYSTEM_ACTIVATE[@]}"
}

cmd:nix-switch-home() {
	cmd:nix-build-home
	cmd:nix-diff-home
	cmd:nix-activate-home
}

cmd:nix-switch-home-locked() {
	DOTFILES_HOME_LOCKED=1 cmd:nix-switch-home
}

cmd:nix-switch-system() {
	cmd:nix-build-system
	cmd:nix-diff-system
	cmd:nix-activate-system
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
	if [[ $(jj log -r '@' --no-graph -T 'if(empty, "true", "false")') != true ]]; then
		jj new
	fi
	nix flake update --accept-flake-config
	cmd:nix-package-update "$@"
	local changed_files
	changed_files="$(jj diff -r @ --name-only)"
	if [[ -z $changed_files ]]; then
		echo "dependencies unchanged, skipping eval and commit"
		return
	fi
	cmd:nix-eval-home
	desc='build(nix): update dependencies'
	printf '%s\n' "$desc" | commit-message-check
	jj commit -m "$desc"
}

cmd:fmt() {
	snapshot
	echo "Formatting..."
	nix fmt --accept-flake-config -- --no-cache
}

cmd:fmt-check() {
	snapshot
	echo "Checking formatting..."
	nix fmt --accept-flake-config -- --no-cache --fail-on-change
}

cmd:lint() {
	cmd:lint-shell
	cmd:lint-python
}

cmd:lint-shell() {
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

cmd:lint-python() {
	snapshot
	echo "Checking Python types..."
	basedpyright --project pyrightconfig.json --warnings
}

cmd:python-check() {
	cmd:lint-python
}

usage() {
	echo "usage: $0 <command>" >&2
	echo "" >&2
	echo "commands:" >&2
	declare -F | sed -n 's/.*cmd://p' | sort | sed 's/^/  /' >&2
}

main() {
	if [[ -z ${1:-} ]]; then
		usage
		exit 1
	fi
	local fn="cmd:$1"
	if ! declare -f "$fn" >/dev/null 2>&1; then
		echo "error: unknown command '${fn#cmd:}'" >&2
		usage
		exit 1
	fi
	shift
	"$fn" "$@"
}

main "$@"
