#!/usr/bin/env bash
# Verify the Claude Code settings behaviors that `default.nix` and
# `settings-overlay.sh` are built on, against the installed `claude` on PATH.
#
# The pin hands Claude Code a `--settings` payload and deletes parts of it so
# the machine-local file can take those settings over. That design rests on five
# undocumented behaviors, one probe each: the flag layer outranking the layers
# below it, an omitted leaf falling through, nested objects merging leaf by
# leaf, `deny` and `ask` outranking a lower-layer `allow`, and arrays unioning
# across layers. Each is measured by running a real session, because none of
# them is observable without one — which is why this is a manual command rather
# than part of the Nix build. It needs network access and a logged-in Claude
# Code session, and it spends a handful of small model calls.
#
# The other half of the same contract — that the precedence chain and the
# `--settings` JSON-string capability are still present in the packaged binary —
# is asserted offline during `./x.sh nix-build-home`.
#
# The probes run `claude` from PATH, which is the launch wrapper: each payload
# lands as a second `--settings` after the wrapper's own pin, so every probe
# also rests on a later occurrence displacing an earlier one (see `mkClaude`
# in `default.nix`). That assumption has no probe or offline assertion of its
# own; if a bump breaks it, the suite fails across the board with the pin's
# values observed, which points at flag stacking rather than at the behavior
# each probe names.
#
# usage: bash verify-settings.sh
#
# Exits 0 when every property holds, and nonzero naming the properties that
# failed. `~/.claude/settings.json` is never written. `~/.claude/.claude.json`
# gains a trust entry for the scratch workspace, removed again on exit and, if a
# run is killed before it can do that, by the next run. Claude Code rewrites
# that file on its own during every session the suite starts, so it is the entry
# rather than the bytes that comes back.
set -euo pipefail

# Every probe pins the model so the suite's cost does not track whatever the
# machine-local file happens to select.
readonly probe_model="claude-haiku-4-5-20251001"

readonly claude_config="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.claude.json"
readonly machine_settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
# Records the scratch workspaces this suite has trusted but not yet untrusted.
readonly trust_ledger="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.claude-verify-settings-trust"

# A probe fails once however many of its assertions fail, and the summary names
# the probes in the order they ran, so membership lives in a set and the order
# lives in a list.
declare -A failure_seen=()
failed_probes=()

record_failure() {
	if ! probe_failed "$1"; then
		failure_seen[$1]=1
		failed_probes+=("$1")
	fi
}

probe_failed() {
	[[ -v failure_seen[$1] ]]
}

check() {
	local probe=$1 what=$2 expected=$3 observed=$4
	[ "$observed" = "$expected" ] && return 0
	printf 'FAIL  %s: %s\n        expected: %s\n        observed: %s\n' \
		"$probe" "$what" "$expected" "$observed" >&2
	record_failure "$probe"
}

check_contains() {
	local probe=$1 what=$2 needle=$3 haystack=$4
	case $haystack in
	*"$needle"*) return 0 ;;
	esac
	printf 'FAIL  %s: %s\n        expected to contain: %s\n        observed: %s\n' \
		"$probe" "$what" "$needle" "$haystack" >&2
	record_failure "$probe"
}

check_excludes() {
	local probe=$1 what=$2 needle=$3 haystack=$4
	case $haystack in
	*"$needle"*)
		printf 'FAIL  %s: %s\n        expected to omit: %s\n        observed: %s\n' \
			"$probe" "$what" "$needle" "$haystack" >&2
		record_failure "$probe"
		;;
	esac
}

report() {
	local probe=$1
	probe_failed "$probe" || printf 'PASS  %s\n' "$probe"
}

command -v claude >/dev/null || {
	echo "claude-verify-settings: no claude on PATH" >&2
	exit 1
}
command -v jq >/dev/null || {
	echo "claude-verify-settings: no jq on PATH" >&2
	exit 1
}
jq -e . "$claude_config" >/dev/null || {
	echo "claude-verify-settings: $claude_config is missing or unparseable" >&2
	exit 1
}

# The suite must be able to prove it left this file alone, and the cheapest
# proof is a digest taken before anything runs. An absent file digests to the
# empty string, so one comparison at the end covers a rewrite, a deletion, and a
# creation alike.
machine_settings_digest() {
	[ -e "$machine_settings" ] || return 0
	shasum -a 256 "$machine_settings" | cut -d' ' -f1
}

machine_settings_digest_before=$(machine_settings_digest)

work=$(mktemp -d)
# `pwd -P` because Claude Code keys trust on the resolved path, and on macOS
# `mktemp -d` hands back a symlinked one.
work=$(cd "$work" && pwd -P)
project="$work/project"
mkdir -p "$project/.claude" "$work/dir-a" "$work/dir-b" "$work/dir-c"
printf 'ALPHA-CONTENT\n' >"$work/dir-a/a.txt"
printf 'BRAVO-CONTENT\n' >"$work/dir-b/b.txt"
printf 'CHARLIE-CONTENT\n' >"$work/dir-c/c.txt"

# Claude Code rewrites this file on its own schedule, so the cleanup deletes
# just our key from whatever the file holds at the time rather than restoring a
# snapshot, and swaps the result in with a rename. A session writing it in the
# same instant can still lose the edit; this is a manual command, so rerunning
# is the recovery.
edit_claude_config() {
	local path=$1 filter=$2

	# The rename is conditional on the filter succeeding and its output still
	# parsing, because the redirect truncates its target before `jq` writes a
	# byte: an interrupted or failing `jq` would otherwise put an empty file
	# over the config. `errexit` cannot be relied on here — the cleanup path
	# calls this from an `||` list, which disables it for the whole body.
	#
	# `printf '%s'` drops the trailing newline `jq` adds, which Claude Code's
	# own writer does not, so an edit that changes nothing leaves the file as it
	# found it.
	PROBE_PROJECT_PATH="$path" jq "$filter" "$claude_config" >"$work/claude.json.next" &&
		jq -e . "$work/claude.json.next" >/dev/null &&
		printf '%s' "$(cat "$work/claude.json.next")" >"$work/claude.json.final" &&
		mv "$work/claude.json.final" "$claude_config"
}

claude_config_trusts_project() {
	PROBE_PROJECT_PATH="$project" jq -r '.projects | has(env.PROBE_PROJECT_PATH)' "$claude_config"
}

# The ledger lives in `~/.claude`, which the `coding-agents` sandbox can write,
# so its path is attacker-controllable: a redirect onto it would follow a
# planted symlink and truncate whatever it points at. Never redirect onto it —
# compose in the scratch directory and rename, which replaces a symlink instead
# of following it — and read it only when it is a regular file, discarding
# anything else as not ours.
write_trust_ledger() {
	local content=$1
	if [ -z "$content" ]; then
		rm -f "$trust_ledger"
		return 0
	fi
	printf '%s\n' "$content" >"$work/trust-ledger" &&
		mv "$work/trust-ledger" "$trust_ledger"
}

read_trust_ledger() {
	if [ -f "$trust_ledger" ] && [ ! -L "$trust_ledger" ]; then
		cat "$trust_ledger"
		return 0
	fi
	rm -f "$trust_ledger"
}

# A run can be killed outright — a closed stdout, a `SIGKILL` — and never reach
# its trap, which would leave the workspace it trusted trusted forever. Recording
# the path before granting and retiring whatever the ledger holds at startup
# bounds that residue to the gap between two runs.
unretired=""
# `|| [ -n "$stale" ]` so a final line without a newline is not dropped.
while IFS= read -r stale || [ -n "$stale" ]; do
	[ -n "$stale" ] || continue
	echo "claude-verify-settings: retiring a trust entry left by an interrupted run: $stale" >&2
	if edit_claude_config "$stale" 'del(.projects[env.PROBE_PROJECT_PATH])'; then
		continue
	fi
	# Keep what could not be retired, so a config that is unwritable right now
	# still gets cleaned up by a later run.
	unretired="$unretired$stale"$'\n'
done < <(read_trust_ledger)
write_trust_ledger "${unretired%$'\n'}"

# Granting trust creates the `projects` map when the config has none, so cleanup
# has to know whether it is deleting a key or the map it invented.
had_projects=$(jq -r 'has("projects")' "$claude_config")

# A pre-existing entry would mean the cleanup below is about to delete somebody
# else's trust grant. `mktemp -d` makes this near-impossible; refuse anyway,
# because the cleanup is unconditional.
if [ "$(claude_config_trusts_project)" != false ]; then
	echo "claude-verify-settings: $claude_config already trusts $project; refusing to manage it" >&2
	exit 1
fi

cleanup() {
	local status=$? filter='del(.projects[env.PROBE_PROJECT_PATH])' remaining
	# Only remove the map when it is the one granting trust invented and nothing
	# else has landed in it since; another writer may have populated it during
	# the run.
	[ "$had_projects" = true ] ||
		filter="$filter | if (.projects | length) == 0 then del(.projects) else . end"
	edit_claude_config "$project" "$filter" || true
	if [ "$(claude_config_trusts_project)" != false ]; then
		echo "claude-verify-settings: could not remove the trust entry for $project from $claude_config; the next run retires it, or remove it by hand" >&2
	else
		# Drop this run's line only. A concurrent run's entry, or one an earlier
		# run could not retire, is not ours to forget.
		remaining=$(read_trust_ledger | grep -vxF -- "$project" || true)
		write_trust_ledger "$remaining" || true
	fi
	rm -rf "$work"
	exit "$status"
}
# An `EXIT` trap alone leaks the trust entry when the run is interrupted or its
# stdout goes away, which is exactly when nobody is watching for the residue.
# The signal handlers exit, which runs the `EXIT` trap.
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
trap 'exit 141' PIPE

# Without this, Claude Code discards the workspace's *permissive* project-scope
# entries — `permissions.allow` and `permissions.additionalDirectories` — and
# says so on stderr. Every probe that grants something from the project layer
# would then measure nothing and report a false pass, so the stderr check in
# `run_probe` treats that message as a failure rather than a warning.
write_trust_ledger "$(
	read_trust_ledger
	printf '%s' "$project"
)"
edit_claude_config "$project" '.projects[env.PROBE_PROJECT_PATH].hasTrustDialogAccepted = true'

# A nested session exports its own identity and transport into the environment.
# Clearing everything Claude Code owns except what the launch wrapper itself
# sets keeps the probes measuring settings rather than inheritance.
claude_env=()
while IFS= read -r name; do
	case $name in
	CLAUDE_CONFIG_DIR | CLAUDE_CODE_DISABLE_BACKGROUND_TASKS) continue ;;
	esac
	claude_env+=(-u "$name")
done < <(env | sed -n 's/^\(CLAUDE[A-Z_0-9]*\)=.*/\1/p' | sort -u)

# Set by `run_probe` for the assertions that follow each call.
probe_out=""
probe_err=""

run_probe() {
	local probe=$1 lower=$2 payload=$3 prompt=$4 status=0

	probe_out="$work/$probe.json"
	probe_err="$work/$probe.err"

	# A lower layer that fails to parse is ignored in `-p` mode without a word
	# on stderr, which would silently turn "the payload wins" into "there was
	# nothing to win against".
	printf '%s' "$lower" | jq -e . >"$project/.claude/settings.json" || {
		check "$probe" "project-layer settings parse" "yes" "no"
		return 1
	}
	printf '%s' "$payload" | jq -e . >/dev/null || {
		check "$probe" "payload parses" "yes" "no"
		return 1
	}
	# `localSettings` sits between the project layer and the flag, so a stale
	# one from an earlier run would intervene unseen.
	rm -f "$project/.claude/settings.local.json"

	(
		cd "$project" &&
			env ${claude_env[@]+"${claude_env[@]}"} claude \
				-p --output-format json --settings "$payload" "$prompt" \
				</dev/null
	) >"$probe_out" 2>"$probe_err" || status=$?

	if [ "$status" -ne 0 ]; then
		check "$probe" "claude exit status" "0" "$status: $(tr '\n' ' ' <"$probe_err")"
		return 1
	fi
	if grep -q 'has not been trusted' "$probe_err"; then
		check "$probe" "workspace trust" "granted" \
			"project-scope entries ignored: $(tr '\n' ' ' <"$probe_err")"
		return 1
	fi
	jq -e . "$probe_out" >/dev/null || {
		check "$probe" "response parses as JSON" "yes" "no"
		return 1
	}
}

# `--output-format json` emits an array of events. Reading it as a single object
# yields `null` for every field, which reads as "nothing was denied" — so every
# extractor below selects its event explicitly.
init_field() {
	jq -r --arg f "$1" '
    [.[] | select(.type == "system" and .subtype == "init")] | last | .[$f] // "«absent»"
  ' "$probe_out"
}

denied_inputs() {
	jq -r '
    [.[] | select(.type == "result") | .permission_denials[]?
     | (.tool_input.command // .tool_input.file_path // .tool_name)] | join(" | ")
  ' "$probe_out"
}

attempted_inputs() {
	jq -r '
    [.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")
     | (.input.command // .input.file_path // .name)] | join(" | ")
  ' "$probe_out"
}

tool_result_text() {
	jq -r '
    [.[] | select(.type == "user") | .message.content[]? | select(.type == "tool_result")
     | (.content | if type == "string" then . else (map(.text // "") | join("\n")) end)]
    | join("\n")
  ' "$probe_out"
}

# `permissions.defaultMode` carries both scalar-layering probes: `system/init`
# reports the resolved mode, so neither probe needs a tool call, and the leaf
# under test is the one the pin actually enforces.
probe_flag_layer_wins() {
	local probe=flag-layer-beats-project-layer
	run_probe "$probe" \
		'{"permissions": {"defaultMode": "plan"}}' \
		"{\"model\": \"$probe_model\", \"permissions\": {\"defaultMode\": \"acceptEdits\"}}" \
		'Reply with OK.' || return 0
	check "$probe" "resolved permission mode" "acceptEdits" "$(init_field permissionMode)"
	report "$probe"
}

probe_omitted_leaf_falls_through() {
	local probe=omitted-leaf-falls-through
	# The payload has to define something, or there is no payload to omit from.
	# `plan` is distinguishable from the `default` that a dropped project layer
	# would produce, so a pass cannot come from the layer being ignored.
	run_probe "$probe" \
		'{"permissions": {"defaultMode": "plan"}}' \
		"{\"model\": \"$probe_model\"}" \
		'Reply with OK.' || return 0
	check "$probe" "resolved permission mode" "plan" "$(init_field permissionMode)"
	report "$probe"
}

# Deleting one leaf of a pinned object has to leave its siblings pinned, which
# only works if Claude Code merges objects per leaf instead of letting the
# highest layer's object replace the rest. `env` is the one pinned-object shape
# whose leaves are directly observable from inside a session.
probe_objects_merge_per_leaf() {
	local probe=objects-merge-per-leaf results
	run_probe "$probe" \
		'{"env": {"PROBE_PROJECT": "from-project", "PROBE_SHARED": "from-project"}}' \
		"{\"model\": \"$probe_model\",
      \"env\": {\"PROBE_FLAG\": \"from-flag\", \"PROBE_SHARED\": \"from-flag\"},
      \"permissions\": {\"allow\": [\"Bash\"]}}" \
		'Run the bash command: env | grep ^PROBE_ | sort' || return 0
	results=$(tool_result_text)
	check_contains "$probe" "flag-only leaf survives" "PROBE_FLAG=from-flag" "$results"
	check_contains "$probe" "project-only leaf survives" "PROBE_PROJECT=from-project" "$results"
	check_contains "$probe" "conflicting leaf resolves upward" "PROBE_SHARED=from-flag" "$results"
	check_excludes "$probe" "conflicting leaf resolves upward" "PROBE_SHARED=from-project" "$results"
	report "$probe"
}

# The pin keeps its `deny` and `ask` rules because a lower layer cannot weaken
# them. `mkdir` is the sentinel: read-only Bash is auto-approved in `-p` mode no
# matter what the rules say, so a probe built on `echo` would pass under every
# configuration.
probe_payload_rules_beat_project_allow() {
	local probe=payload-rules-beat-project-allow
	local project_allow='{"permissions": {"allow": ["Bash(mkdir:*)"]}}'

	# Control first: without a payload rule the sentinel runs. Without this, a
	# denial below would be indistinguishable from `mkdir` being unrunnable.
	if run_probe "$probe" "$project_allow" \
		"{\"model\": \"$probe_model\"}" \
		'Run the bash command: mkdir probe-control'; then
		check "$probe" "project-layer allow lets the sentinel run" "" "$(denied_inputs)"
		check "$probe" "control created its directory" "yes" \
			"$([ -d "$project/probe-control" ] && echo yes || echo no)"
	fi

	if run_probe "$probe" "$project_allow" \
		"{\"model\": \"$probe_model\", \"permissions\": {\"deny\": [\"Bash(mkdir:*)\"]}}" \
		'Run the bash command: mkdir probe-deny'; then
		check_contains "$probe" "payload deny was attempted" "mkdir probe-deny" "$(attempted_inputs)"
		check_contains "$probe" "payload deny beat the project allow" "mkdir probe-deny" "$(denied_inputs)"
		check_contains "$probe" "denial came from a deny rule" "has been denied" "$(tool_result_text)"
		check "$probe" "denied sentinel had no effect" "no" \
			"$([ -d "$project/probe-deny" ] && echo yes || echo no)"
	fi

	if run_probe "$probe" "$project_allow" \
		"{\"model\": \"$probe_model\", \"permissions\": {\"ask\": [\"Bash(mkdir:*)\"]}}" \
		'Run the bash command: mkdir probe-ask'; then
		check_contains "$probe" "payload ask beat the project allow" "mkdir probe-ask" "$(denied_inputs)"
		check "$probe" "asked sentinel had no effect" "no" \
			"$([ -d "$project/probe-ask" ] && echo yes || echo no)"
	fi

	# The other direction: a restrictive rule from below still applies even when
	# the payload grants the tool outright, which is why a machine-local `ask`
	# can tighten the pin but never loosen it.
	if run_probe "$probe" '{"permissions": {"ask": ["Bash(mkdir:*)"]}}' \
		"{\"model\": \"$probe_model\", \"permissions\": {\"allow\": [\"Bash\"]}}" \
		'Run the bash command: mkdir probe-project-ask'; then
		check_contains "$probe" "project-layer ask survives a payload allow" \
			"mkdir probe-project-ask" "$(denied_inputs)"
	fi

	report "$probe"
}

# Arrays union rather than the highest layer replacing them, which is what lets
# the pin carry `permissions.allow` without classifying it: a machine can add to
# it and never subtract.
probe_arrays_union() {
	local probe=arrays-union-across-layers results
	local project_dirs
	project_dirs=$(jq -nc --arg a "$work/dir-a" '{permissions: {additionalDirectories: [$a]}}')
	local payload
	payload=$(jq -nc --arg m "$probe_model" --arg b "$work/dir-b" \
		'{model: $m, permissions: {additionalDirectories: [$b]}}')

	if run_probe "$probe" "$project_dirs" "$payload" \
		"Read the files $work/dir-a/a.txt and $work/dir-b/b.txt, then reply with both contents."; then
		results=$(tool_result_text)
		check "$probe" "neither read was denied" "" "$(denied_inputs)"
		check_contains "$probe" "project-layer directory stayed readable" "ALPHA-CONTENT" "$results"
		check_contains "$probe" "payload directory is readable" "BRAVO-CONTENT" "$results"
	fi

	# Without this control an "allowed" result proves nothing: it could mean
	# reads outside the workspace are ungated rather than that both layers'
	# entries applied.
	if run_probe "$probe" "$project_dirs" "$payload" \
		"Read the file $work/dir-c/c.txt and reply with its contents."; then
		check_contains "$probe" "an unlisted directory is still gated" \
			"$work/dir-c/c.txt" "$(attempted_inputs)"
		check_contains "$probe" "an unlisted directory is still gated" \
			"$work/dir-c/c.txt" "$(denied_inputs)"
	fi

	report "$probe"
}

echo "claude-verify-settings: probing $(command -v claude) ($(claude --version 2>/dev/null || echo 'version unknown'))"
echo "claude-verify-settings: scratch workspace $project"

probe_flag_layer_wins
probe_omitted_leaf_falls_through
probe_objects_merge_per_leaf
probe_payload_rules_beat_project_allow
probe_arrays_union

check machine-settings-untouched "$machine_settings digest" \
	"$machine_settings_digest_before" "$(machine_settings_digest)"
report machine-settings-untouched

if [ ${#failed_probes[@]} -gt 0 ]; then
	printf 'claude-verify-settings: failed: %s\n' "${failed_probes[*]}" >&2
	exit 1
fi
echo "claude-verify-settings: every measured settings behavior still holds"
