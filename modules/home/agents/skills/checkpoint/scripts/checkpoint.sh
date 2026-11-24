#!/usr/bin/env bash

# Creates and lists session checkpoints: one Markdown file per piece of work,
# named after the second it was created, in the ignored `.agent/checkpoints/`
# store. Agents edit a checkpoint in place; this script never changes one.
#
#   checkpoint.sh new --workspace <abs-workspace>
#   checkpoint.sh list --workspace <abs-workspace>
#
# `new` prints the absolute path of a new, empty checkpoint. `list` prints one
# `<checkpoint path>\t<goal>` line per checkpoint, newest first, where the goal
# is the file's first `# ` heading, or `(no goal)` when it has none. Exit status
# is 2 on a usage error, agent-store's status when it cannot resolve the store,
# and 1 on any other failure, with nothing on stdout.

set -euo pipefail

readonly CHECKPOINT_PATTERN='^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}\.md$'
readonly MAX_CREATE_ATTEMPTS=5

usage() {
	cat >&2 <<'EOF'
usage: checkpoint.sh new --workspace <abs-workspace>
       checkpoint.sh list --workspace <abs-workspace>
EOF
	exit 2
}

fail() {
	printf 'checkpoint: %s\n' "$1" >&2
	exit 1
}

# Prints the checkpoint store for the workspace; agent-store resolves the main
# checkout the workspace shares and keeps the store untracked and ignored.
store_dir() {
	agent-store dir --workspace "$1" checkpoints
}

# Creates an empty checkpoint named after the current second. When another
# session took that second, waits for the next one; any other failure to create
# the file stops at once.
create_checkpoint() {
	local store=$1
	local attempt timestamp path

	for ((attempt = 1; attempt <= MAX_CREATE_ATTEMPTS; attempt++)); do
		timestamp=${CHECKPOINT_TIMESTAMP:-$(date '+%Y-%m-%d-%H%M%S')}
		path="$store/$timestamp.md"
		[[ $(basename "$path") =~ $CHECKPOINT_PATTERN ]] || fail 'invalid checkpoint timestamp'

		# noclobber makes bash create the file with O_EXCL, so two sessions in
		# the same second never share a checkpoint.
		if (set -o noclobber && : >"$path") 2>/dev/null; then
			printf '%s\n' "$path"
			return 0
		fi
		[[ -e $path ]] || fail "cannot create checkpoint: $path"
		((attempt == MAX_CREATE_ATTEMPTS)) || sleep 1
	done
	fail "no free checkpoint name after $MAX_CREATE_ATTEMPTS attempts"
}

# Prints the checkpoint's first `# ` heading, which the skill keeps as the goal.
goal_of() {
	local line

	while IFS= read -r line || [[ -n $line ]]; do
		if [[ $line == '# '* ]]; then
			printf '%s\n' "${line#'# '}"
			return 0
		fi
	done <"$1"
	printf '(no goal)\n'
}

cmd_new() {
	[[ $# -eq 2 && $1 == --workspace ]] || usage
	local store

	store=$(store_dir "$2")
	create_checkpoint "$store"
}

cmd_list() {
	[[ $# -eq 2 && $1 == --workspace ]] || usage
	local store path
	local checkpoints=()

	store=$(store_dir "$2")
	shopt -s nullglob
	for path in "$store"/*.md; do
		[[ -f $path && $(basename "$path") =~ $CHECKPOINT_PATTERN ]] && checkpoints+=("$path")
	done
	shopt -u nullglob
	((${#checkpoints[@]} > 0)) || return 0

	while IFS= read -r path; do
		printf '%s\t%s\n' "$path" "$(goal_of "$path")"
	done < <(printf '%s\n' "${checkpoints[@]}" | sort -r)
}

[[ $# -ge 1 ]] || usage
command=$1
shift
case $command in
new) cmd_new "$@" ;;
list) cmd_list "$@" ;;
*) usage ;;
esac
