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
	policy_path="${jj_shim%/*}:${denied%/*}"

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
	[[ -z "$(command -v cat || true)" ]]
' bash "$denied" "$jj_shim" "$git_askpass" "$ssh_askpass" "$cat_path"

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
	grep -Fq "$expected" "$workdir/stderr"
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
