#!/usr/bin/env bash

set -euo pipefail

denied=$1
jj_shim=$2
probe=$3
git_askpass=$4
ssh_askpass=$5
real_jj=$6
cat_path=$7
python=$8
ssh_add=$9
ssh_agent=${10}
ssh_keygen=${11}
real_git=${12}
git_shim=${13}
workdir=$(mktemp -d)
test_ssh_agent_pid=

cleanup() {
	if [[ -n $test_ssh_agent_pid ]]; then
		kill "$test_ssh_agent_pid" 2>/dev/null || true
	fi
	rm -rf "$workdir"
}
trap cleanup EXIT
mkdir -p "$workdir/home/.config"

# The probe's child shell expands the policy variables after the wrapper exports them.
# shellcheck disable=SC2016
HOME="$workdir/home" \
	XDG_CONFIG_HOME="$workdir/home/.config" \
	GIT_CONFIG_GLOBAL=/dev/null \
	EDITOR=preserved-editor \
	VISUAL=preserved-visual \
	CI=preserved-ci \
	GIT_SSH_COMMAND=preserved-git-ssh-command \
	PATH=preserved-path \
	"$probe" "$BASH" -c '
	set -euo pipefail
	denied=$1
	jj_shim=$2
	git_askpass=$3
	ssh_askpass=$4
	cat_path=$5
	git_shim=$6
	policy_path="${git_shim%/*}:${jj_shim%/*}:${denied%/*}"

	[[ "$JJ_EDITOR" == "$denied jj editor" ]]
	[[ "$GIT_EDITOR" == "$denied git editor" ]]
	[[ "$GIT_SEQUENCE_EDITOR" == "$denied git sequence-editor" ]]
	[[ "$GIT_ASKPASS" == "$git_askpass" ]]
	[[ "$SSH_ASKPASS" == "$ssh_askpass" ]]
	[[ "$SSH_ASKPASS_REQUIRE" == force ]]
	[[ "$GIT_TERMINAL_PROMPT" == 0 ]]
	[[ "$JJ_PAGER" == "$cat_path" ]]
	[[ "$GIT_PAGER" == "$cat_path" ]]
	[[ "$PAGER" == "$cat_path" ]]
	[[ "$EDITOR" == preserved-editor ]]
	[[ "$VISUAL" == preserved-visual ]]
	[[ "$CI" == preserved-ci ]]
	[[ "$GIT_SSH_COMMAND" == preserved-git-ssh-command ]]
	[[ "$PATH" == "$policy_path:preserved-path" ]]
	[[ "$(command -v agent-interactive-denied)" == "$denied" ]]
	[[ "$(command -v jj)" == "$jj_shim" ]]
	[[ "$(command -v git)" == "$git_shim" ]]
	[[ -z "$(command -v cat || true)" ]]
' bash "$denied" "$jj_shim" "$git_askpass" "$ssh_askpass" "$cat_path" "$git_shim"

status=0
"$ssh_askpass" 'credential-looking prompt: secret' >"$workdir/ssh-stdout" 2>"$workdir/ssh-stderr" || status=$?
[[ $status -eq 1 ]]
[[ ! -s "$workdir/ssh-stdout" ]]
grep -Fq 'blocked ssh askpass in a coding-agent session' "$workdir/ssh-stderr"

status=0
"$git_askpass" 'credential-looking prompt: secret' >"$workdir/git-stdout" 2>"$workdir/git-stderr" || status=$?
[[ $status -eq 1 ]]
[[ ! -s "$workdir/git-stdout" ]]
grep -Fq 'blocked git askpass in a coding-agent session' "$workdir/git-stderr"

run_under_pty() {
	"$python" - "$@" <<'PY'
import errno
import os
import pty
import select
import signal
import sys
import time


timeout_seconds = float(sys.argv[1])
argv = sys.argv[2:]
pid, descriptor = pty.fork()
if pid == 0:
    os.execv(argv[0], argv)

output = []
status = None
timed_out = False
deadline = time.monotonic() + timeout_seconds
while status is None:
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        timed_out = True
        try:
            os.killpg(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        _, status = os.waitpid(pid, 0)
        break

    readable, _, _ = select.select([descriptor], [], [], min(remaining, 0.1))
    if readable:
        try:
            chunk = os.read(descriptor, 4096)
        except OSError as error:
            if error.errno != errno.EIO:
                raise
        else:
            if chunk:
                output.append(chunk)

    waited_pid, waited_status = os.waitpid(pid, os.WNOHANG)
    if waited_pid == pid:
        status = waited_status

while select.select([descriptor], [], [], 0)[0]:
    try:
        chunk = os.read(descriptor, 4096)
    except OSError as error:
        if error.errno == errno.EIO:
            break
        raise
    if not chunk:
        break
    output.append(chunk)

os.close(descriptor)
sys.stdout.buffer.write(b"".join(output))
sys.exit(124 if timed_out else os.waitstatus_to_exitcode(status))
PY
}

"$ssh_keygen" -q -t ed25519 -N '' -f "$workdir/agent-key"
"$ssh_keygen" -q -t ed25519 -N test-passphrase -f "$workdir/encrypted-key"
eval "$("$ssh_agent" -a "$workdir/agent.sock" -s)" >/dev/null
test_ssh_agent_pid=$SSH_AGENT_PID

run_under_pty 10 "$probe" "$ssh_add" "$workdir/agent-key" >"$workdir/ssh-agent-add-output"
if grep -Fq 'blocked ssh askpass in a coding-agent session' "$workdir/ssh-agent-add-output"; then
	exit 1
fi
"$ssh_add" -l >/dev/null

status=0
run_under_pty 10 "$probe" "$ssh_add" "$workdir/encrypted-key" \
	>"$workdir/ssh-agent-denied-output" || status=$?
[[ $status -ne 0 ]]
[[ $status -ne 124 ]]
grep -Fq 'blocked ssh askpass in a coding-agent session' "$workdir/ssh-agent-denied-output"

run_agent() {
	HOME="$workdir/home" \
		XDG_CONFIG_HOME="$workdir/home/.config" \
		GIT_CONFIG_GLOBAL=/dev/null \
		"$probe" "$@"
}

expect_agent_failure() {
	local expected=$1
	shift

	local status=0
	run_agent "$@" >"$workdir/stdout" 2>"$workdir/stderr" || status=$?
	[[ $status -ne 0 ]]
	grep -Fq -- "$expected" "$workdir/stderr"
}

# Asserts that agent-policy refuses the command under RULE_ID with the tool's
# message prefix and tells the agent how to request approval for that rule.
expect_policy_refusal() {
	local tool=$1 rule_id=$2
	shift 2

	expect_agent_failure "$tool (agent policy): $rule_id refused this command" "$@"
	grep -Fq -- "AGENT_POLICY_APPROVE=$rule_id" "$workdir/stderr"
}

git_repo="$workdir/git-repo"
run_agent git init -q "$git_repo"
run_agent git -C "$git_repo" config user.name 'Test User'
run_agent git -C "$git_repo" config user.email test@example.com
printf 'initial\n' >"$git_repo/tracked"
run_agent git -C "$git_repo" add tracked
expect_agent_failure 'blocked git editor in a coding-agent session' git -C "$git_repo" commit
run_agent git -C "$git_repo" commit -q -m initial
printf 'second\n' >>"$git_repo/tracked"
run_agent git -C "$git_repo" commit -q -am second
expect_agent_failure 'blocked git sequence-editor in a coding-agent session' \
	git -C "$git_repo" rebase -i --root
expect_agent_failure 'blocked git askpass in a coding-agent session' \
	bash -c 'printf "protocol=https\\nhost=example.invalid\\n\\n" | git credential fill'

shim_version=$(run_agent jj --version)
real_version=$("$real_jj" --version)
[[ $shim_version == "$real_version" ]]
shim_status=0
real_status=0
run_agent jj agent-policy-invalid-command >/dev/null 2>&1 || shim_status=$?
"$real_jj" agent-policy-invalid-command >/dev/null 2>&1 || real_status=$?
[[ $shim_status -eq $real_status ]]
[[ $shim_status -ne 0 ]]

jj_repo="$workdir/jj-repo"
run_agent git init -q "$jj_repo"
run_agent git -C "$jj_repo" config user.name 'Test User'
run_agent git -C "$jj_repo" config user.email test@example.com
printf 'initial\n' >"$jj_repo/tracked"
run_agent git -C "$jj_repo" add tracked
run_agent git -C "$jj_repo" commit -q -m initial
run_agent jj git init --colocate "$jj_repo"
diff_editor=$(run_agent jj -R "$jj_repo" config get ui.diff-editor)
merge_editor=$(run_agent jj -R "$jj_repo" config get ui.merge-editor)
[[ $diff_editor == *"$denied"*diff-editor* ]]
[[ $merge_editor == *"$denied"*merge-editor* ]]
expect_agent_failure 'blocked jj editor in a coding-agent session' jj -R "$jj_repo" describe
printf 'changed\n' >"$jj_repo/tracked"
expect_agent_failure 'blocked jj diff-editor in a coding-agent session' jj -R "$jj_repo" diffedit

# Reproduces an agent abandoning other workspaces' working-copy commits through
# a revset rooted at trunk. `other` sits on trunk with a bookmark; `stacked`
# builds on the agent's stack, which must stay mutable for the agent.
mkdir -p "$workdir/home/.config/jj"
cat >"$workdir/home/.config/jj/config.toml" <<'TOML'
user.name = "Test User"
user.email = "test@example.com"
revset-aliases."trunk()" = "present(main)"
TOML
workspaces="$workdir/workspaces"
mkdir -p "$workspaces"
in_workspace() {
	local name=$1
	shift
	run_agent jj --quiet -R "$workspaces/$name" "$@"
}
expect_workspace_failure() {
	local expected=$1 name=$2
	shift 2
	expect_agent_failure "$expected" jj -R "$workspaces/$name" "$@"
}
change_id() {
	in_workspace "$1" log --no-graph -r "$2" -T 'change_id'
}

run_agent jj --quiet git init "$workspaces/default"
printf 'base\n' >"$workspaces/default/base"
in_workspace default commit -m base
in_workspace default bookmark create main -r @-
for name in agent other stacked; do
	in_workspace default workspace add --name "$name" "$workspaces/$name"
done
in_workspace agent new main
printf 'agent\n' >"$workspaces/agent/agent"
in_workspace agent commit -m 'agent work'
in_workspace agent bookmark create agentb -r @-
leftover=$(change_id agent @)
in_workspace agent new
in_workspace other new main
in_workspace other bookmark create otherb -r @
in_workspace stacked new agentb
other_wc=$(change_id other other@)
trunk=$(change_id agent main)

expect_workspace_failure 'is immutable' agent \
	abandon -r "$trunk:: & empty() & ~@ & description(exact:\"\")"
[[ $(change_id agent other@) == "$other_wc" ]]
[[ $(in_workspace agent bookmark list -T 'name ++ "\n"' otherb) == otherb ]]
expect_workspace_failure 'is immutable' agent describe -m taken other@
expect_workspace_failure 'is immutable' agent rebase -s "$trunk+" -o "$trunk"

in_workspace agent abandon "$leftover"
in_workspace agent describe -m 'agent work, described' agentb
printf 'fix\n' >>"$workspaces/agent/agent"
in_workspace agent squash --into agentb
in_workspace stacked workspace update-stale
[[ $(in_workspace stacked log --no-graph -r @- -T 'description.first_line()') == 'agent work, described' ]]

# Bookmarks have no mechanical guard; `jj op revert` restores one deleted from
# another workspace's stack, even after other workspaces ran operations.
in_workspace agent bookmark delete otherb
deletion=$(in_workspace agent op log --no-graph --limit 1 -T 'id.short()')
in_workspace default bookmark create unrelated -r main
in_workspace agent op revert "$deletion"
[[ $(in_workspace agent bookmark list -T 'name ++ "\n"' otherb) == otherb ]]

# `--ignore-immutable` anywhere before `--` needs the user's approval of
# jj.ignore-immutable itself; the retired override and other approvals do not
# lift it.
other_description=$(in_workspace agent log --no-graph -r other@ -T 'description')
for approval in unset '' 1 git.push jj.git-push; do
	if [[ $approval == unset ]]; then
		expect_policy_refusal jj jj.ignore-immutable \
			jj -R "$workspaces/agent" --ignore-immutable describe -m taken other@
	else
		AGENT_POLICY_APPROVE=$approval expect_policy_refusal jj jj.ignore-immutable \
			jj -R "$workspaces/agent" describe --ignore-immutable -m taken other@
	fi
done
JJ_AGENT_ALLOW_IGNORE_IMMUTABLE=1 expect_policy_refusal jj jj.ignore-immutable \
	jj -R "$workspaces/agent" --ignore-immutable describe -m taken other@
[[ $(in_workspace agent log --no-graph -r other@ -T 'description') == "$other_description" ]]
# After `--` the token is an operand, not the option.
[[ $(in_workspace agent util exec -- "$python" -c 'import sys; print(sys.argv[1])' --ignore-immutable) == --ignore-immutable ]]
AGENT_POLICY_APPROVE=jj.ignore-immutable in_workspace agent --ignore-immutable describe -m taken other@
[[ $(in_workspace agent log --no-graph -r other@ -T 'description.first_line()') == taken ]]
AGENT_POLICY_APPROVE=git.push,jj.ignore-immutable \
	in_workspace agent --ignore-immutable describe -m 'taken twice' other@
[[ $(in_workspace agent log --no-graph -r other@ -T 'description.first_line()') == 'taken twice' ]]

# The real binary never sees the approval, so it cannot leak into commands the
# approved one runs.
# shellcheck disable=SC2016 # Python reads the variable, not the shell.
approval_seen=$(AGENT_POLICY_APPROVE=jj.ignore-immutable in_workspace agent --ignore-immutable util exec -- \
	"$python" -c 'import os; print(os.environ.get("AGENT_POLICY_APPROVE", "unset"))')
[[ $approval_seen == unset ]]

# The engine adds nothing else to the environment either: the real binary sees
# the caller's PATH and no Python settings of its own.
# shellcheck disable=SC2016 # Python reads the variables, not the shell.
read_python_environment='import os; print(os.environ["PATH"]); print(os.environ.get("PYTHONNOUSERSITE", "unset"))'
caller_environment=$(
	unset PYTHONNOUSERSITE
	run_agent "$python" -c "$read_python_environment"
)
tool_environment=$(
	unset PYTHONNOUSERSITE
	in_workspace agent util exec -- "$python" -c "$read_python_environment"
)
[[ $tool_environment == "$caller_environment" ]]
[[ ${tool_environment##*$'\n'} == unset ]]

# Agent jj pushes through the Nix git rather than whichever `git` is first on
# PATH; the push goes to a local bare remote, so no credential prompt can occur.
[[ $(run_agent jj -R "$jj_repo" config get git.executable-path) == "$real_git" ]]
push_remote="$workdir/push-remote.git"
"$real_git" init -q --bare "$push_remote"
push_repo="$workdir/push-repo"
run_agent jj --quiet git init "$push_repo"
run_agent jj --quiet -R "$push_repo" git remote add origin "$push_remote"
printf 'pushed\n' >"$push_repo/pushed"
run_agent jj --quiet -R "$push_repo" commit -m pushed
run_agent jj --quiet -R "$push_repo" bookmark create pushed -r @-
run_agent jj --quiet -R "$push_repo" bookmark track pushed --remote origin
run_agent jj --quiet -R "$push_repo" git push --remote origin --bookmark pushed
[[ $("$real_git" --git-dir "$push_remote" rev-parse pushed) == "$(run_agent jj -R "$push_repo" log --no-graph -r pushed -T 'commit_id')" ]]

# The git shim passes everything but a top-level `push` to the Nix git,
# including the option-only `--exec-path` query.
[[ $(run_agent git --version) == "$("$real_git" --version)" ]]
[[ $(run_agent git --exec-path) == "$("$real_git" --exec-path)" ]]

# A direct git push is blocked however the global options precede it; the
# remote keeps its ref after each attempt.
git_push_repo="$workdir/git-push-repo"
"$real_git" -C "$push_remote" branch -f git-pushed pushed
remote_before=$("$real_git" --git-dir "$push_remote" rev-parse git-pushed)
run_agent git init -q -b git-pushed "$git_push_repo"
run_agent git -C "$git_push_repo" config user.name 'Test User'
run_agent git -C "$git_push_repo" config user.email test@example.com
run_agent git -C "$git_push_repo" remote add origin "$push_remote"
printf 'git push\n' >"$git_push_repo/tracked"
run_agent git -C "$git_push_repo" add tracked
run_agent git -C "$git_push_repo" commit -q -m 'git push'
local_head=$(run_agent git -C "$git_push_repo" rev-parse HEAD)
# shellcheck disable=SC2016 # The child shell expands its own positional argument.
expect_policy_refusal git git.push bash -c 'cd "$1" && git push -f origin git-pushed' bash "$git_push_repo"
grep -Fq -- 'jj git push' "$workdir/stderr"
expect_policy_refusal git git.push git -C "$git_push_repo" push -f origin git-pushed
expect_policy_refusal git git.push git -c push.default=current -C "$git_push_repo" push -f origin git-pushed
expect_policy_refusal git git.push git --git-dir="$git_push_repo/.git" push -f origin git-pushed
expect_policy_refusal git git.push git --git-dir "$git_push_repo/.git" --no-pager push -f origin git-pushed
# Only an approval of git.push itself lifts the refusal; the retired override,
# a boolean, an empty list, and other rules' approvals do not.
GIT_AGENT_ALLOW_PUSH=1 expect_policy_refusal git git.push git -C "$git_push_repo" push -f origin git-pushed
for approval in '' 1 jj.ignore-immutable; do
	AGENT_POLICY_APPROVE=$approval expect_policy_refusal git git.push \
		git -C "$git_push_repo" push -f origin git-pushed
done
[[ $("$real_git" --git-dir "$push_remote" rev-parse git-pushed) == "$remote_before" ]]

AGENT_POLICY_APPROVE=git.push run_agent git -C "$git_push_repo" push -q -f "$push_remote" git-pushed
[[ $("$real_git" --git-dir "$push_remote" rev-parse git-pushed) == "$local_head" ]]

# Agent jj still publishes with the git shim first on PATH.
printf 'pushed again\n' >>"$push_repo/pushed"
run_agent jj --quiet -R "$push_repo" commit -m 'pushed again'
run_agent jj --quiet -R "$push_repo" bookmark set pushed -r @-
run_agent jj --quiet -R "$push_repo" git push --remote origin --bookmark pushed
[[ $("$real_git" --git-dir "$push_remote" rev-parse pushed) == "$(run_agent jj -R "$push_repo" log --no-graph -r pushed -T 'commit_id')" ]]

# jj.git-push runs pushes that name each bookmark and only add or fast-forward
# remote bookmarks, with the allowed globals in any position.
in_push_repo() {
	run_agent jj --quiet -R "$push_repo" "$@"
}
local_commit() {
	run_agent jj -R "$push_repo" log --no-graph -r "$1" -T 'commit_id'
}
remote_commit() {
	"$real_git" --git-dir "$push_remote" rev-parse --verify -q "refs/heads/$1" || true
}
remote_refs() {
	"$real_git" --git-dir "$push_remote" for-each-ref --format='%(refname) %(objectname)'
}
commit_in_push_repo() {
	printf '%s\n' "$1" >>"$push_repo/pushed"
	in_push_repo commit -m "$1"
}
expect_push_refusal() {
	expect_policy_refusal jj jj.git-push jj -R "$push_repo" "$@"
}

commit_in_push_repo added
in_push_repo bookmark create added -r @-
run_agent jj git push --no-pager -b added -R "$push_repo" --color=never --remote origin
[[ $(remote_commit added) == "$(local_commit added)" ]]
commit_in_push_repo forward
in_push_repo bookmark set added -r @-
run_agent jj -R "$push_repo" git --quiet push --bookmark=added --ignore-working-copy
[[ $(remote_commit added) == "$(local_commit added)" ]]
commit_in_push_repo 'forward with debug'
in_push_repo bookmark set added -r @-
run_agent jj --debug -R "$push_repo" git push -b exact:added >"$workdir/stdout" 2>"$workdir/stderr"
[[ $(remote_commit added) == "$(local_commit added)" ]]
commit_in_push_repo change
in_push_repo git push -c @-
change_bookmark=$(run_agent jj -R "$push_repo" log --no-graph -r @- -T 'local_bookmarks.map(|b| b.name()).join(",")')
[[ $change_bookmark == push-* ]]
[[ $(remote_commit "$change_bookmark") == "$(local_commit @-)" ]]
in_push_repo git push --named named=@- --remote=origin
[[ $(remote_commit named) == "$(local_commit @-)" ]]
# jj accepts a name containing `@` only as a quoted string literal; the quoted
# form names exactly one bookmark, so the preview and the push both pass.
commit_in_push_repo 'quoted name'
in_push_repo bookmark create '"quoted@2"' -r @-
remote_before=$(remote_refs)
run_agent jj -R "$push_repo" git push --remote origin --bookmark '"quoted@2"' --dry-run >"$workdir/stdout" 2>&1
grep -Fq -- 'bookmark: "quoted@2" [add to' "$workdir/stdout"
[[ $(remote_refs) == "$remote_before" ]]
in_push_repo git push -b '"quoted@2"'
[[ $(remote_commit quoted@2) == "$(local_commit '"quoted@2"')" ]]
[[ $(run_agent jj git push --help) == *Usage* ]]
[[ $(run_agent jj -R "$push_repo" git push -h) == *Usage* ]]

# `--ignore-immutable` is judged by its own rule, not the push allowlist,
# which passes this push of an unchanged bookmark.
expect_policy_refusal jj jj.ignore-immutable jj -R "$push_repo" git push --ignore-immutable -b added
if grep -Fq -- 'jj.git-push' "$workdir/stderr"; then
	exit 1
fi

# Bulk, pattern, configuration, and operation-changing pushes are refused
# before jj runs, each naming the safe form.
remote_before=$(remote_refs)
expect_push_refusal git push
grep -Fq -- 'names nothing to act on' "$workdir/stderr"
grep -Fq -- 'jj git push -b <name>' "$workdir/stderr"
expect_push_refusal --quiet git push --remote origin
for option in --all --tracked --deleted -r=@- --revision=@- \
	--allow-private --allow-conflicts --allow-empty-description --frobnicate; do
	expect_push_refusal git push -b added "$option"
	grep -Fq -- "\`${option%%=*}\` is not an allowed option for \`jj git push\`" "$workdir/stderr"
done
expect_push_refusal git push -b added -t v1
expect_push_refusal git push -b added --tag v1
expect_push_refusal git push -b added -o ci.skip
expect_push_refusal git push -b added --option ci.skip
expect_push_refusal git push -b '*'
grep -Fq -- 'is a pattern' "$workdir/stderr"
expect_push_refusal git push -b 'glob:a*'
expect_push_refusal git push --bookmark added --bookmark='added|named'
expect_push_refusal git push -b added --remote '*'
expect_push_refusal git push --named 'na*=@-'
expect_push_refusal --config ui.color=never git push -b added
# shellcheck disable=SC2016 # The backticks are literal message text.
grep -Fq -- 'global option `--config` is not allowed for `jj git push`' "$workdir/stderr"
expect_push_refusal git push -b added --config-file /dev/null
expect_push_refusal --at-operation @ git push -b added
expect_push_refusal git push -b added --no-integrate-operation
[[ $(remote_refs) == "$remote_before" ]]

# The dry-run check refuses force pushes, deletions, and more bookmark
# changes than named targets; `--dry-run` itself passes without the check.
in_push_repo new 'added-'
commit_in_push_repo sideways
in_push_repo bookmark set added -r @- --allow-backwards
expect_push_refusal git push -b added
# shellcheck disable=SC2016 # The backticks are literal message text.
grep -Fq -- '`added` (move sideways from' "$workdir/stderr"
run_agent jj -R "$push_repo" git push --dry-run -b added >"$workdir/stdout" 2>"$workdir/stderr"
grep -Fq -- 'move sideways from' "$workdir/stderr"
in_push_repo bookmark set added -r 'added-' --allow-backwards
expect_push_refusal --quiet git push -b added
# shellcheck disable=SC2016 # The backticks are literal message text.
grep -Fq -- '`added` (move backward from' "$workdir/stderr"
in_push_repo bookmark delete named
expect_push_refusal git push -b named
# shellcheck disable=SC2016 # The backticks are literal message text.
grep -Fq -- '`named` (delete from' "$workdir/stderr"
commit_in_push_repo 'excess one'
commit_in_push_repo 'excess two'
expect_push_refusal git push -c 'description(glob:"excess*")'
grep -Fq -- 'changes 2 bookmarks but the command names only 1 target' "$workdir/stderr"
expect_push_refusal git push -c 'all()'
[[ $(remote_refs) == "$remote_before" ]]

# Only an approval of jj.git-push itself lets a refused push through.
for approval in '' 1 jj.ignore-immutable git.push; do
	AGENT_POLICY_APPROVE=$approval expect_push_refusal git push -b added
done
[[ $(remote_refs) == "$remote_before" ]]
AGENT_POLICY_APPROVE=jj.git-push in_push_repo git push -b added
[[ $(remote_commit added) == "$(local_commit added)" ]]
AGENT_POLICY_APPROVE=git.push,jj.git-push in_push_repo git push -b named
[[ -z $(remote_commit named) ]]
# Approval also lifts the allowlist's option refusals.
AGENT_POLICY_APPROVE=jj.git-push in_push_repo git push -b added --allow-private
