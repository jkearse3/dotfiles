#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
SOCKET_PIDS=()

cleanup() {
	local pid
	for pid in "${SOCKET_PIDS[@]}"; do
		[[ -n $pid ]] || continue
		kill "$pid" 2>/dev/null || true
		wait "$pid" 2>/dev/null || true
	done
	rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

stop_socket() {
	local socket_index=$1
	local pid=${SOCKET_PIDS[$socket_index]}
	kill "$pid"
	wait "$pid" 2>/dev/null || true
	SOCKET_PIDS[socket_index]=""
}

start_socket() {
	local socket_path=$1
	mkdir -p "$(dirname "$socket_path")"
	python3 - "$socket_path" <<'PY' &
import socket
import struct
import sys

server = socket.socket(socket.AF_UNIX)
server.bind(sys.argv[1])
server.listen()
while True:
    connection, _ = server.accept()
    with connection:
        connection.recv(5)
        connection.sendall(struct.pack(">IBI", 5, 12, 0))
PY
	SOCKET_PIDS+=("$!")

	local _
	for _ in {1..100}; do
		[[ -S $socket_path ]] && return
		sleep 0.01
	done
	return 1
}

normalized_socket="$TEST_ROOT/normalized.sock"
darwin_socket="$TEST_ROOT/darwin.sock"
start_socket "$normalized_socket"
start_socket "$darwin_socket"

# shellcheck disable=SC1090
source "$REPO_ROOT/x.sh"

[[ $(select_1password_ssh_agent_socket Darwin "$normalized_socket" "$darwin_socket") == "$normalized_socket" ]]
stop_socket 0
[[ $(select_1password_ssh_agent_socket Darwin "$normalized_socket" "$darwin_socket") == "$darwin_socket" ]]
[[ -z $(select_1password_ssh_agent_socket Linux "$normalized_socket" "$darwin_socket") ]]
stop_socket 1
[[ -z $(select_1password_ssh_agent_socket Darwin "$normalized_socket" "$darwin_socket") ]]

assert_inherited_socket_preserved() {
	local HOME="$TEST_ROOT/empty"
	local SSH_AUTH_SOCK=/ambient/agent.sock
	export HOME SSH_AUTH_SOCK

	mkdir -p "$HOME"
	configure_1password_ssh_agent
	[[ $SSH_AUTH_SOCK == /ambient/agent.sock ]]
}
assert_inherited_socket_preserved
