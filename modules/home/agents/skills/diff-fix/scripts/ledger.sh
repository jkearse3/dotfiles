#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

usage() {
	printf '%s\n' \
		'usage: ledger.sh record <ledger> <event>  (event JSON object on stdin)' \
		'       ledger.sh state <ledger>' \
		'       ledger.sh context <ledger> review' \
		'       ledger.sh context <ledger> fix <owner> [<id>...]' >&2
	exit 2
}

# A ledger is an append-only JSON Lines log of events. `record` validates one
# event, stamps it with a sequence number and time, appends it, and prints the
# assigned finding ID for a `finding` event or the sequence number otherwise.
# `state` folds the log into current findings and counters, so an orchestrator
# that lost its context can resume from the file alone. `context` selects what
# the next reviewer or fixer receives. The log has a single writer, the
# orchestrating session.
if [[ $# -lt 2 ]]; then
	usage
fi
command=$1
ledger=$2
shift 2

role=
owner=
finding_ids=()
case $command in
record)
	if [[ $# -ne 1 ]]; then
		usage
	fi
	event=$1
	;;
state)
	if [[ $# -ne 0 ]]; then
		usage
	fi
	;;
context)
	if [[ ${1:-} == review && $# -eq 1 ]]; then
		role=review
	elif [[ ${1:-} == fix && $# -ge 2 && -n $2 ]]; then
		role=fix
		owner=$2
		finding_ids=("${@:3}")
	else
		usage
	fi
	;;
*)
	usage
	;;
esac

if ! command -v jq >/dev/null 2>&1; then
	printf '%s\n' 'ledger: jq is required but not on PATH' >&2
	exit 1
fi
if [[ -L $ledger || ! -f $ledger ]]; then
	printf '%s\n' "ledger: not a regular file: $ledger" >&2
	exit 1
fi

# Each event kind lists its required string, string-array, and enum fields.
# Finding references must name a recorded finding, and a finding owner must be
# one of the `run` event's target change IDs. The `run` event's `criteria` holds
# the declared criteria and context every review receives, so a resumed session
# cannot drop them. A `decision` without an `id` is a standing decision for the
# whole run.
#
# Finding statuses change only along FINDING_TRANSITIONS: a new `design` or
# `question` finding starts `pending-decision` so no fixer acts on it before the
# user decides, any other new finding starts `open`, a `status` event follows
# the table, a `land` moves `open` findings to `fixed`, and a finding decision
# moves any finding to its effect. A finding a decision opened carries a user
# request, so only another decision may settle it.
# shellcheck disable=SC2016 # jq program, not shell expansion.
RECORD_PROGRAM='
($log | ledger_state) as $state
|
def fail($message): error("ledger: \($kind): \($message)");
def need_string($key): if (.[$key] | type) == "string" and .[$key] != "" then . else fail("\($key) must be a non-empty string") end;
def need_string_array($key): if (.[$key] | type) == "array" and all(.[$key][]; type == "string") then . else fail("\($key) must be an array of strings") end;
def need_enum($key; $allowed): if (.[$key] as $value | $allowed | index([$value])) then . else fail("\($key) must be one of \($allowed | join(", "))") end;
def finding_ids: [$log[] | select(.event == "finding") | .id];
def need_finding($key): if (.[$key] as $id | finding_ids | index([$id])) then . else fail("\($key) names no recorded finding") end;
def need_target_owner: if (.owner as $owner | $log[0].target | index([$owner])) then . else fail("owner is not a run target change ID: \(.owner)") end;
def statuses: ["open", "fixed", "pending-decision", "settled"];
def recorded_finding($id): $state.findings[] | select(.id == $id);
def need_initial_status:
  (if .category == "design" or .category == "question" then "pending-decision" else "open" end) as $initial
  | if .status == $initial then . else fail("a new \(.category) finding must start \($initial)") end;
def open_ids: [$state.findings[] | select(.status == "open") | .id];
def need_transition:
  .id as $id
  | .status as $to
  | recorded_finding($id) as $finding
  | if $finding.status == "open" and $to == "settled" and ($finding.decisions | last | .effect) == "open" then fail("a decision opened \($id); only another decision may move it to \($to)")
    elif FINDING_TRANSITIONS[$finding.status] | index([$to]) then .
    else fail("\($id) cannot move from \($finding.status) to \($to)")
    end;

if type != "object" then fail("event must be a JSON object")
elif $kind != "run" and ($log | length) == 0 then fail("the first event must be run")
elif $kind == "run" and ($log | length) > 0 then fail("run may be recorded only once")
elif $kind == "run" then need_string_array("target") | need_string("base") | need_string("criteria")
elif $kind == "review" then need_string_array("revisions") | need_enum("verdict"; ["pass", "non-pass", "blocked"])
elif $kind == "finding" then need_string("owner") | need_target_owner | need_string("category") | need_string("priority") | need_string("location") | need_string("mechanism") | need_enum("status"; ["open", "pending-decision"]) | need_initial_status
elif $kind == "status" then need_finding("id") | need_enum("status"; statuses) | need_string("evidence") | need_transition
elif $kind == "attempt" then need_finding("id") | need_enum("outcome"; ["fixed", "rejected", "escalated", "unverified"]) | need_string("summary")
elif $kind == "land" then need_string("from") | need_string("to") | need_string_array("findings") | ((.findings - finding_ids) as $unknown | if $unknown == [] then . else fail("findings names no recorded finding: \($unknown | join(", "))") end) | ((.findings - open_ids) as $closed | if $closed == [] then . else fail("findings are not open: \($closed | join(", "))") end)
elif $kind == "checkpoint" then need_string("summary")
elif $kind == "decision" then need_string("decision") | if has("id") then need_finding("id") | need_enum("effect"; ["settled", "open"]) else . end
else fail("unknown event kind")
end
| {seq: (($log | length) + 1), at: $now, event: $kind}
  + (if $kind == "finding" then {id: "F\(finding_ids | length + 1)"} + del(.id) else . end
    | del(.seq, .at, .event))
'

# The status changes a `status` event may make, keyed by the current status.
# Re-raising a `fixed` or `settled` finding, or an open one a fixer rejected
# with evidence, asks the user; an open finding the next reviewer declines with
# a reason settles. `fixed` comes only from a `land`, and a `pending-decision`
# finding leaves that status only through a decision.
FINDING_TRANSITIONS='
def FINDING_TRANSITIONS: {
  "open": ["settled", "pending-decision"],
  "fixed": ["pending-decision"],
  "settled": ["pending-decision"],
  "pending-decision": []
};
'

# Replay the log in order. A checkpoint resets the full-review count, a landing
# marks its findings fixed, and a finding decision sets that finding's status.
# shellcheck disable=SC2016 # jq program, not shell expansion.
LEDGER_STATE='
def ledger_state: reduce .[] as $event (
  {
    run: null,
    full_reviews: 0,
    full_reviews_since_checkpoint: 0,
    last_review: null,
    checkpoints: 0,
    standing_decisions: [],
    landings: [],
    order: [],
    findings: {}
  };
  if $event.event == "run" then
    .run = ($event | del(.seq, .at, .event))
  elif $event.event == "review" then
    .full_reviews += 1
    | .full_reviews_since_checkpoint += 1
    | .last_review = $event
  elif $event.event == "finding" then
    .order += [$event.id]
    | .findings[$event.id] = ($event | del(.seq, .at, .event)) + {
        attempts: [],
        decisions: []
      }
  elif $event.event == "status" then
    .findings[$event.id].status = $event.status
    | .findings[$event.id].evidence = $event.evidence
  elif $event.event == "attempt" then
    .findings[$event.id].attempts += [$event | del(.at, .event, .id)]
  elif $event.event == "land" then
    .landings += [$event | del(.at, .event)]
    | reduce $event.findings[] as $id (.;
        .findings[$id].status = "fixed"
        | .findings[$id].evidence = "landed in \($event.to)"
      )
  elif $event.event == "checkpoint" then
    .checkpoints += 1
    | .full_reviews_since_checkpoint = 0
  elif $event.event == "decision" and ($event | has("id")) then
    .findings[$event.id].decisions += [$event | del(.at, .event, .id)]
    | .findings[$event.id].status = $event.effect
  elif $event.event == "decision" then
    .standing_decisions += [$event | del(.at, .event)]
  else . end
)
| .findings = [.order[] as $id | .findings[$id]]
| del(.order)
| .status_counts = (.findings | group_by(.status) | map({key: .[0].status, value: length}) | from_entries);
'

# Both roles receive the run criteria. A reviewer receives settled conclusions
# to re-check, open findings carried from an earlier round as claims to confirm,
# including any a fixer rejected, and user decisions, each as a brief finding:
# its latest attempt and its decisions without their history. A fixer receives
# its owning revision's open findings in full with their attempt history, and
# briefly every pending-decision finding so it can escalate a fix that depends
# on one, settled conclusions, and user decisions. Each finding appears once
# per context: a listed finding carries its own decisions, and `decided` holds
# only decided findings no other list includes. Finding IDs given after the
# owner restrict the open findings to those IDs, so a fixer re-dispatched after
# partial verification receives only the rest; each must name an open finding
# of that owner. The owner must be a run target change ID, so a mistyped owner
# fails rather than yielding an empty open list.
# shellcheck disable=SC2016 # jq program, not shell expansion.
CONTEXT_PROGRAM='
def brief:
  {id, owner, category, priority, location, mechanism, status}
  + (if has("evidence") then {evidence} else {} end)
  + (if .attempts != [] then {last_attempt: (.attempts | last | {outcome, summary})} else {} end)
  + (if .decisions != [] then {decisions: [.decisions[] | {decision, effect}]} else {} end);
def with_status($status): [.findings[] | select(.status == $status)];
def brief_with_status($status): [with_status($status)[] | brief];
def decided_beyond($listed):
  [$listed[] | arrays | .[].id] as $ids
  | [.findings[] | select(.decisions != [] and (.id as $id | $ids | index([$id]) | not)) | brief];
def owner_open: [with_status("open")[] | select(.owner == $owner)];
def selected_open:
  $ARGS.positional as $ids
  | ($ids - [owner_open[].id]) as $unknown
  | if $ids == [] then owner_open
    elif $unknown == [] then [owner_open[] | select(.id as $id | $ids | index([$id]))]
    else "ledger: context: not an open finding of \($owner): \($unknown | join(", "))\n" | halt_error(1)
    end;

if $role == "fix" and ((.run.target // []) | index([$owner]) | not) then
  "ledger: context: owner is not a run target change ID: \($owner)\n" | halt_error(1)
elif $role == "review" then
  {
    criteria: .run.criteria,
    settled: brief_with_status("settled"),
    open: brief_with_status("open")
  } as $listed
  | $listed + {
    decided: decided_beyond($listed),
    standing_decisions: .standing_decisions
  }
else
  {
    criteria: .run.criteria,
    open: selected_open,
    pending_decision: brief_with_status("pending-decision"),
    settled: brief_with_status("settled")
  } as $listed
  | $listed + {
    decided: decided_beyond($listed),
    standing_decisions: .standing_decisions
  }
end
'

case $command in
record)
	if ! input=$(jq -cs 'if length == 1 then .[0] else error end' 2>/dev/null); then
		printf '%s\n' 'ledger: event must be one JSON value on stdin' >&2
		exit 1
	fi
	now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
	line=$(jq -nc \
		--arg kind "$event" \
		--arg now "$now" \
		--slurpfile log "$ledger" \
		--argjson input "$input" \
		"$FINDING_TRANSITIONS $LEDGER_STATE \$input | $RECORD_PROGRAM" 2>&1) || {
		printf '%s\n' "${line#jq: error (at <unknown>): }" >&2
		exit 1
	}
	printf '%s\n' "$line" >>"$ledger"
	jq -r 'if .event == "finding" then .id else .seq end' <<<"$line"
	;;
state)
	jq -s "$LEDGER_STATE ledger_state" "$ledger"
	;;
context)
	jq -s "$LEDGER_STATE ledger_state" "$ledger" |
		jq --arg role "$role" --arg owner "$owner" "$CONTEXT_PROGRAM" --args "${finding_ids[@]}"
	;;
esac
