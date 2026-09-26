#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

usage() {
	printf '%s\n' \
		'usage: land.sh --workspace <absolute-workspace> [--description-file <path>] <ledger> <owner> [<finding-id>...]' >&2
	exit 2
}

# Land the verified working copy into its parent, a target revision of the run,
# and record the landing. The working copy must be a child of <owner>. Its
# changes are squashed into <owner>, keeping the owner's description unless
# --description-file supplies a validated replacement; an empty working copy
# with a replacement lands a description-only fix. The finding IDs are the open
# findings of <owner> the landing fixes; a conflict resolution names none.
#
# Before mutating, land.sh checks that <owner> is a run target, every named
# finding is open and owned by <owner>, the working copy is a child of <owner>,
# and the landing changes something: a non-empty working copy or a
# --description-file. A rejected landing changes nothing. After squashing, it
# confirms <owner> now holds exactly the noted working-copy tree and is not
# conflicted, records the `land` event, and prints the conflicted descendants:
# `target-conflict <change-id>` lines for target revisions to resolve, earliest
# first, then `outside-conflict <change-id>` lines for other descendants.
workspace=
description_file=
while [[ $# -gt 0 ]]; do
	case $1 in
	--workspace)
		[[ $# -ge 2 ]] || usage
		workspace=$2
		shift 2
		;;
	--description-file)
		[[ $# -ge 2 ]] || usage
		description_file=$2
		shift 2
		;;
	*)
		break
		;;
	esac
done
if [[ $workspace != /* || $# -lt 2 ]]; then
	usage
fi
ledger=$1
owner=$2
shift 2
finding_ids=("$@")

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LEDGER="$SCRIPT_DIR/ledger.sh"

fail() {
	printf 'land: %s\n' "$1" >&2
	exit 1
}

# Print a jj log template for a revset; extra arguments pass through to jj log.
jj_log() {
	jj -R "$workspace" log --no-graph -r "$1" -T "$2" "${@:3}"
}

# Check the landing against the ledger and the repository before mutating.
if [[ -n $description_file && ! -f $description_file ]]; then
	fail "description file is not a regular file: $description_file"
fi

state=$("$LEDGER" state "$ledger")
jq -e --arg owner "$owner" '.run.target | index([$owner])' <<<"$state" >/dev/null ||
	fail "owner is not a run target change ID: $owner"

closed=$(jq -rn --argjson state "$state" \
	'[$state.findings[] | select(.status == "open") | .id] as $open | [$ARGS.positional[] | select(. as $id | $open | index([$id]) | not)] | join(", ")' \
	--args "${finding_ids[@]}")
[[ -z $closed ]] || fail "findings are not open: $closed"

foreign=$(jq -rn --argjson state "$state" --arg owner "$owner" \
	'[$state.findings[] | select(.owner == $owner) | .id] as $owned | [$ARGS.positional[] | select(. as $id | $owned | index([$id]) | not)] | join(", ")' \
	--args "${finding_ids[@]}")
[[ -z $foreign ]] || fail "findings are not owned by $owner: $foreign"

parent=$(jj_log '@-' 'change_id ++ "\n"')
[[ $parent == "$owner" ]] || fail "the working copy is not a child of $owner"
if [[ -z $description_file && $(jj_log '@' 'empty') == true ]]; then
	fail "the working copy is empty and no description file is given"
fi

working_copy=$(jj_log '@' 'commit_id')
from=$(jj_log "$owner" 'commit_id')

# Squash, then confirm the owner holds exactly the verified tree.
if [[ -n $description_file ]]; then
	jj -R "$workspace" squash --quiet --from "$working_copy" --into "$owner" --message "$(<"$description_file")"
else
	jj -R "$workspace" squash --quiet --from "$working_copy" --into "$owner" --use-destination-message
fi
to=$(jj_log "$owner" 'commit_id')

[[ -z $(jj -R "$workspace" diff --from "$working_copy" --to "$owner" --summary) ]] ||
	fail "$owner does not match the landed working copy $working_copy"
[[ $(jj_log "$owner" 'conflict') == false ]] ||
	fail "the landing conflicts the owning revision $owner"

jq -nc --arg from "$from" --arg to "$to" '{from: $from, to: $to, findings: $ARGS.positional}' --args "${finding_ids[@]}" |
	"$LEDGER" record "$ledger" land >/dev/null

# Report conflicted descendants: target revisions first, then the rest.
target_revset=$(jq -r '.run.target | join(" | ")' <<<"$state")
conflicted="descendants($owner) & conflicts()"
jj_log "($conflicted) & ($target_revset)" '"target-conflict " ++ change_id ++ "\n"' --reversed
jj_log "($conflicted) ~ ($target_revset) ~ @" '"outside-conflict " ++ change_id ++ "\n"' --reversed
