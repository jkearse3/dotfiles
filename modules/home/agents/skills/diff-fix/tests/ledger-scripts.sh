#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PREPARE_LEDGER="$SCRIPT_DIR/../scripts/prepare-ledger.sh"
LEDGER="$SCRIPT_DIR/../scripts/ledger.sh"
TMPDIR_ROOT=$(mktemp -d)
TMPDIR_ROOT=$(cd "$TMPDIR_ROOT" && pwd -P)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# The helper runs from a directory unrelated to any fixture so the target is
# chosen only by --workspace. The path contains a space so quoting regressions
# surface.
UNRELATED_CWD="$TMPDIR_ROOT/unrelated cwd"
mkdir -p "$UNRELATED_CWD"

export JJ_CONFIG=/dev/null JJ_USER=test JJ_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

fail() {
	printf 'not ok - %s\n' "$1" >&2
	exit 1
}

assert_eq() {
	local expected=$1
	local actual=$2
	local description=$3

	[[ $actual == "$expected" ]] || fail "$description: expected '$expected', got '$actual'"
	printf 'ok - %s\n' "$description"
}

# Callers may override the deterministic timestamp through LEDGER_TIMESTAMP.
prepare() {
	(cd "$UNRELATED_CWD" && LEDGER_TIMESTAMP=${LEDGER_TIMESTAMP:-2026-01-02-030405} "$PREPARE_LEDGER" "$@")
}

# Run the helper expecting failure, and assert its status and diagnostic.
assert_failure() {
	local expected_status=$1
	local expected_diagnostic=$2
	local description=$3
	shift 3
	local status=0
	local stderr

	stderr=$(prepare "$@" 2>&1 >/dev/null) || status=$?
	assert_eq "$expected_status" "$status" "$description exits $expected_status"
	assert_eq "$expected_diagnostic" "$stderr" "$description reports its cause"
}

# jj default workspace: the store lives at its root, ignores itself, and never
# enters the working-copy revision.
JJ_REPO="$TMPDIR_ROOT/jj repo"
jj git init --quiet "$JJ_REPO"
mkdir -p "$JJ_REPO/nested"
path=$(prepare --workspace "$JJ_REPO/nested" 'Feature/Stack Fix!')
assert_eq "$JJ_REPO/.agent/diff-fix/2026-01-02-030405-feature-stack-fix.jsonl" "$path" \
	'jj default workspace reserves a ledger at its root'
assert_eq '*' "$(<"$JJ_REPO/.agent/diff-fix/.gitignore")" 'store ignores its contents'
assert_eq '' "$(jj -R "$JJ_REPO" diff --summary)" 'ledger stays out of the working-copy revision'

path=$(prepare --workspace "$JJ_REPO" 'Feature/Stack Fix!')
assert_eq "$JJ_REPO/.agent/diff-fix/2026-01-02-030405-feature-stack-fix--2.jsonl" "$path" \
	'repeated reservation takes a collision suffix'

# jj secondary workspace: the store belongs to that workspace, not the default.
JJ_SECONDARY="$TMPDIR_ROOT/jj secondary"
jj -R "$JJ_REPO" workspace add --quiet "$JJ_SECONDARY"
path=$(prepare --workspace "$JJ_SECONDARY")
assert_eq "$JJ_SECONDARY/.agent/diff-fix/2026-01-02-030405-ledger.jsonl" "$path" \
	'jj secondary workspace keeps its own store'
assert_eq '' "$(jj -R "$JJ_SECONDARY" diff --summary)" \
	'secondary workspace ledger stays out of its working-copy revision'

# A tracked store is never repurposed.
TRACKED="$TMPDIR_ROOT/tracked"
jj git init --quiet "$TRACKED"
mkdir -p "$TRACKED/.agent/diff-fix"
printf 'kept\n' >"$TRACKED/.agent/diff-fix/notes.md"
jj -R "$TRACKED" status >/dev/null
assert_failure 1 'prepare-ledger: .agent/diff-fix must be entirely untracked' \
	'tracked store' --workspace "$TRACKED"

# Symlinked store components and ignore files the store does not own are
# rejected.
GUARDED="$TMPDIR_ROOT/guarded"
GUARDED_STORE="$GUARDED/.agent/diff-fix"
ELSEWHERE="$TMPDIR_ROOT/elsewhere"
jj git init --quiet "$GUARDED"
mkdir -p "$ELSEWHERE"
ln -s "$ELSEWHERE" "$GUARDED/.agent"
assert_failure 1 'prepare-ledger: .agent/diff-fix must not traverse a symlink' \
	'symlinked .agent' --workspace "$GUARDED"
rm "$GUARDED/.agent"

mkdir -p "$GUARDED/.agent"
ln -s "$ELSEWHERE" "$GUARDED_STORE"
assert_failure 1 'prepare-ledger: .agent/diff-fix must not traverse a symlink' \
	'symlinked store' --workspace "$GUARDED"
rm "$GUARDED_STORE"

mkdir -p "$GUARDED_STORE"
printf '*\n' >"$ELSEWHERE/ignore"
ln -s "$ELSEWHERE/ignore" "$GUARDED_STORE/.gitignore"
assert_failure 1 "prepare-ledger: $GUARDED_STORE/.gitignore must not be a symlink" \
	'symlinked ignore file' --workspace "$GUARDED"
rm "$GUARDED_STORE/.gitignore"

printf '%s\n' '*' '!*.jsonl' >"$GUARDED_STORE/.gitignore"
assert_failure 1 "prepare-ledger: $GUARDED_STORE/.gitignore must contain exactly '*'" \
	'weakened ignore file' --workspace "$GUARDED"
printf '*\n' >"$GUARDED_STORE/.gitignore"

LEDGER_TIMESTAMP=../escape assert_failure 1 'prepare-ledger: invalid ledger timestamp' \
	'invalid timestamp' --workspace "$GUARDED"

# A pre-existing symlink at a candidate path, even a dangling one, stays
# untouched while reservation advances to the next suffix.
existing_symlink="$GUARDED_STORE/2026-01-02-030405-existing.jsonl"
ln -s "$ELSEWHERE/missing" "$existing_symlink"
path=$(prepare --workspace "$GUARDED" existing)
assert_eq "$GUARDED_STORE/2026-01-02-030405-existing--2.jsonl" "$path" \
	'an existing symlink forces the next suffix'
assert_eq "$ELSEWHERE/missing" "$(readlink "$existing_symlink")" 'the existing symlink keeps its target'
[[ ! -e $ELSEWHERE/missing ]] || fail 'the existing symlink target must not be created'
printf '%s\n' 'ok - the existing symlink target is not created'

# Malformed input fails before any VCS inspection.
assert_failure 2 'usage: prepare-ledger.sh --workspace <absolute-workspace> [slug]' \
	'relative workspace' --workspace relative
assert_failure 2 'prepare-ledger: not inside a jj workspace' \
	'non-repository workspace' --workspace "$UNRELATED_CWD"

# Ledger events: validated, appended in order, and replayed into state.
EVENTS="$TMPDIR_ROOT/events.jsonl"
: >"$EVENTS"

record() {
	local event=$1
	local json=$2

	"$LEDGER" record "$EVENTS" "$event" <<<"$json"
}

# Run the recorder expecting failure, and assert its status and diagnostic.
assert_record_failure() {
	local expected_diagnostic=$1
	local description=$2
	shift 2
	local status=0
	local stderr

	stderr=$(record "$@" 2>&1 >/dev/null) || status=$?
	assert_eq 1 "$status" "$description exits 1"
	assert_eq "$expected_diagnostic" "$stderr" "$description reports its cause"
}

state() {
	"$LEDGER" state "$EVENTS" | jq -c "$1"
}

context() {
	"$LEDGER" context "$EVENTS" "$@" | jq -c '[.[] | if type == "array" then map(.id // .decision) else . end]'
}

# The ledger path must name an existing regular file, not a symlink.
missing_status=0
missing_stderr=$("$LEDGER" state "$TMPDIR_ROOT/missing.jsonl" 2>&1 >/dev/null) || missing_status=$?
assert_eq 1 "$missing_status" 'missing ledger exits 1'
assert_eq "ledger: not a regular file: $TMPDIR_ROOT/missing.jsonl" "$missing_stderr" 'missing ledger reports its cause'
ln -s "$EVENTS" "$TMPDIR_ROOT/linked.jsonl"
EVENTS="$TMPDIR_ROOT/linked.jsonl" assert_record_failure "ledger: not a regular file: $TMPDIR_ROOT/linked.jsonl" \
	'symlinked ledger' run '{"target":["abc"],"base":"main","criteria":"none"}'
assert_eq '' "$(<"$EVENTS")" 'a rejected symlinked ledger leaves its target unchanged'

assert_record_failure 'ledger: review: the first event must be run' \
	'event before run' review '{"revisions":[],"verdict":"pass"}'
assert_record_failure 'ledger: run: target must be an array of strings' \
	'run with a single-string target' run '{"target":"abc","base":"main","criteria":"none"}'
assert_record_failure 'ledger: run: criteria must be a non-empty string' \
	'run without criteria' run '{"target":["a","b"],"base":"main"}'
assert_eq 1 "$(record run '{"target":["a","b"],"base":"main","criteria":"none"}')" 'run is event 1'
assert_eq '"none"' "$(state .run.criteria)" 'state keeps the run criteria for a resumed session'
assert_record_failure 'ledger: run: run may be recorded only once' \
	'second run' run '{"target":["abc"],"base":"main","criteria":"none"}'
record decision '{"decision":"fix design findings too"}' >/dev/null
record review '{"revisions":["abc"],"verdict":"non-pass"}' >/dev/null
assert_eq F1 "$(record finding '{"id":"ignored","owner":"a","category":"bug","priority":"low","location":"x:1","mechanism":"m","status":"open"}')" \
	'finding IDs are assigned, not supplied'
assert_record_failure 'ledger: finding: owner is not a run target change ID: ab' \
	'finding owned outside the target' finding '{"owner":"ab","category":"bug","priority":"low","location":"x:1","mechanism":"m","status":"open"}'
assert_record_failure 'ledger: status: status must be one of open, fixed, disputed, pending-decision, settled' \
	'unknown status' status '{"id":"F1","status":"done","evidence":"e"}'
assert_record_failure 'ledger: attempt: id names no recorded finding' \
	'unknown finding' attempt '{"id":"F9","outcome":"fixed","summary":"s"}'
assert_record_failure 'ledger: decision: effect must be one of settled, open' \
	'finding decision without effect' decision '{"id":"F1","decision":"d"}'
assert_record_failure 'ledger: land: findings names no recorded finding: F9' \
	'land with unknown finding' land '{"from":"a","to":"b","findings":["F1","F9"]}'
assert_record_failure 'ledger: land: findings must be an array of strings' \
	'land with malformed findings' land '{"from":"a","to":"b","findings":[{"x":1}]}'
assert_record_failure 'ledger: review: revisions must be an array of strings' \
	'review with malformed revisions' review '{"revisions":[1],"verdict":"pass"}'
assert_record_failure 'ledger: event must be one JSON value on stdin' \
	'malformed event' status 'not json'
assert_record_failure 'ledger: event must be one JSON value on stdin' \
	'two JSON values' checkpoint '{"summary":"a"} {"summary":"b"}'

# Findings for two owners in every status, so the context views can be told
# apart.
record attempt '{"id":"F1","outcome":"fixed","summary":"s"}' >/dev/null
record status '{"id":"F1","status":"fixed","evidence":"e"}' >/dev/null
record finding '{"owner":"a","category":"design","priority":"low","location":"y:2","mechanism":"n","status":"pending-decision"}' >/dev/null
record finding '{"owner":"a","category":"bug","priority":"low","location":"z:3","mechanism":"o","status":"open"}' >/dev/null
record finding '{"owner":"b","category":"bug","priority":"low","location":"w:4","mechanism":"p","status":"open"}' >/dev/null
record finding '{"owner":"a","category":"bug","priority":"low","location":"v:5","mechanism":"q","status":"disputed"}' >/dev/null
record land '{"from":"a","to":"b","findings":["F1"]}' >/dev/null
assert_eq '{"full":1,"counts":{"disputed":1,"fixed":1,"open":2,"pending-decision":1}}' \
	"$(state '{full: .full_reviews_since_checkpoint, counts: .status_counts}')" \
	'state replays statuses and counts full reviews'

record checkpoint '{"summary":"decide"}' >/dev/null
record decision '{"id":"F2","decision":"leave as is","effect":"settled"}' >/dev/null
assert_eq '{"full":0,"F2":"settled","standing":["fix design findings too"]}' \
	"$(state '{full: .full_reviews_since_checkpoint, F2: .findings[1].status, standing: [.standing_decisions[].decision]}')" \
	'a checkpoint resets the review count and decisions set status'

assert_eq '[["F2"],["F5"],["F3","F4"],["F2"],["fix design findings too"]]' "$(context review)" \
	'a reviewer receives settled, disputed, open, and decided findings'
assert_eq '[["F3"],[],["F2"],["F2"],["fix design findings too"]]' "$(context fix a)" \
	'a fixer receives only its owner'"'"'s open findings'

# A fixer receives every pending-decision finding, whatever its owner, so it can
# escalate a fix that depends on one.
record finding '{"owner":"b","category":"design","priority":"low","location":"t:7","mechanism":"s","status":"pending-decision"}' >/dev/null
assert_eq '[["F3"],["F6"],["F2"],["F2"],["fix design findings too"]]' "$(context fix a)" \
	'a fixer receives pending-decision findings of every owner'
assert_eq '[["F2"],["F5"],["F3","F4"],["F2"],["fix design findings too"]]' "$(context review)" \
	'a reviewer does not receive pending-decision findings'

# Finding IDs after the owner restrict a fixer's open findings, for a fixer
# re-dispatched with only the findings that failed verification.
record finding '{"owner":"a","category":"bug","priority":"low","location":"u:6","mechanism":"r","status":"open"}' >/dev/null
assert_eq '[["F3","F7"],["F6"],["F2"],["F2"],["fix design findings too"]]' "$(context fix a)" \
	'a fixer without finding IDs receives all its owner'"'"'s open findings'
assert_eq '[["F7"],["F6"],["F2"],["F2"],["fix design findings too"]]' "$(context fix a F7)" \
	'a fixer with finding IDs receives only those open findings'

context_status=0
context_stderr=$("$LEDGER" context "$EVENTS" fix a F7 F4 F2 2>&1 >/dev/null) || context_status=$?
assert_eq 1 "$context_status" 'a finding ID outside the owner'"'"'s open findings exits 1'
assert_eq 'ledger: context: not an open finding of a: F4, F2' "$context_stderr" \
	'a finding ID outside the owner'"'"'s open findings reports its cause'

context_status=0
context_stderr=$("$LEDGER" context "$EVENTS" fix c 2>&1 >/dev/null) || context_status=$?
assert_eq 1 "$context_status" 'a fixer owner outside the run target exits 1'
assert_eq 'ledger: context: owner is not a run target change ID: c' "$context_stderr" \
	'a fixer owner outside the run target reports its cause'
