#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "usage: omp-settings-merge-test <omp-settings-merge>" >&2
	exit 2
fi

merge=$1
tmp=$(mktemp -d)
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf -- "$tmp"' EXIT

seed=$tmp/seed.yml
cat >"$seed" <<'YAML'
defaultThinkingLevel: medium
modelRoles:
  default: openai-codex/gpt-5.6-sol
startup:
  quiet: true
YAML

# A first activation creates a private, writable regular file.
fresh_dir=$tmp/fresh/agent
"$merge" "$fresh_dir" "$seed"
fresh=$fresh_dir/config.yml
test -f "$fresh"
test ! -L "$fresh"
test "$(stat -c '%a' "$fresh")" = 600
test "$(yq -r '.modelRoles.default' "$fresh")" = openai-codex/gpt-5.6-sol

# OMP-owned values win while newly declared defaults fill missing keys.
live_dir=$tmp/live
live=$live_dir/config.yml
mkdir -p "$live_dir"
cat >"$live" <<'YAML'
modelRoles:
  default: anthropic/claude-sonnet-4-6
startup:
  quiet: false
userSetting: retained
YAML
"$merge" "$live_dir" "$seed"
test "$(yq -r '.modelRoles.default' "$live")" = anthropic/claude-sonnet-4-6
test "$(yq -r '.defaultThinkingLevel' "$live")" = medium
test "$(yq -r '.startup.quiet' "$live")" = false
test "$(yq -r '.userSetting' "$live")" = retained

# Preserve OMP's existing config.yaml fallback rather than shadowing it with a
# newly created config.yml.
fallback_dir=$tmp/fallback
fallback=$fallback_dir/config.yaml
mkdir -p "$fallback_dir"
printf 'userSetting: from-config-yaml\n' >"$fallback"
"$merge" "$fallback_dir" "$seed"
test ! -e "$fallback_dir/config.yml"
test "$(yq -r '.userSetting' "$fallback")" = from-config-yaml

# Empty YAML is OMP's supported spelling for an empty settings mapping.
empty_dir=$tmp/empty
mkdir -p "$empty_dir"
: >"$empty_dir/config.yml"
"$merge" "$empty_dir" "$seed"
test "$(yq -r '.defaultThinkingLevel' "$empty_dir/config.yml")" = medium

# OMP resolves writable symlink targets and preserves the user-managed link.
linked_source=$tmp/linked-source.yml
printf 'userSetting: linked\n' >"$linked_source"
linked_dir=$tmp/linked
linked=$linked_dir/config.yml
mkdir -p "$linked_dir"
ln -s "$linked_source" "$linked"
"$merge" "$linked_dir" "$seed"
test -L "$linked"
test "$(yq -r '.userSetting' "$linked_source")" = linked
test "$(yq -r '.defaultThinkingLevel' "$linked_source")" = medium

# A read-only store-style target cannot support OMP's lock or atomic rewrite;
# replace only that kind of symlink without mutating its source.
store_dir=$tmp/store
store_source=$store_dir/config.yml
mkdir -p "$store_dir"
printf 'userSetting: store-source\n' >"$store_source"
chmod 444 "$store_source"
chmod 555 "$store_dir"
store_link_dir=$tmp/store-link
store_link=$store_link_dir/config.yml
mkdir -p "$store_link_dir"
ln -s "$store_source" "$store_link"
source_before=$(cksum "$store_source")
"$merge" "$store_link_dir" "$seed"
test -f "$store_link"
test ! -L "$store_link"
test "$(cksum "$store_source")" = "$source_before"

# For a chained dangling symlink, OMP locks and replaces only the immediate
# target. The merge must wait on that same lock rather than resolving the chain.
locked_dir=$tmp/locked
locked=$locked_dir/config.yml
locked_immediate=$locked_dir/intermediate.yml
locked_final=$locked_dir/missing-final.yml
mkdir -p "$locked_dir"
ln -s "$(basename "$locked_immediate")" "$locked"
ln -s "$(basename "$locked_final")" "$locked_immediate"
ready=$tmp/lock-ready
release=$tmp/lock-release
python3 - "$locked_immediate.lock" "$ready" "$release" <<'PY' &
import errno
import fcntl
import os
from pathlib import Path
import socket
import sys
import time

lock_path, ready_path, release_path = map(Path, sys.argv[1:])
if sys.platform.startswith("linux"):
    import xxhash

    lock_bytes = os.path.abspath(lock_path).encode()
    high = xxhash.xxh64(lock_bytes, seed=0x4F4D502D4C4F434B).intdigest()
    low = xxhash.xxh64(lock_bytes, seed=0x50492D46494C454C).intdigest()
    lock_socket = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    lock_socket.bind(f"\0omp-file-lock-{high:016x}{low:016x}")
    ready_path.touch()
    while not release_path.exists():
        time.sleep(0.01)
    lock_socket.close()
else:
    with lock_path.open("a+b") as lock_file:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        ready_path.touch()
        while not release_path.exists():
            time.sleep(0.01)
PY
lock_holder=$!
while [[ ! -e $ready ]]; do sleep 0.01; done
"$merge" "$locked_dir" "$seed" &
blocked_merge=$!
sleep 0.2
kill -0 "$blocked_merge"
touch "$release"
wait "$lock_holder"
wait "$blocked_merge"
test -L "$locked"
test -f "$locked_immediate"
test ! -L "$locked_immediate"
test ! -e "$locked_final"
test "$(yq -r '.defaultThinkingLevel' "$locked")" = medium

# Invalid live YAML fails without replacing the original file.
invalid_dir=$tmp/invalid
invalid=$invalid_dir/config.yml
mkdir -p "$invalid_dir"
printf 'broken: [\n' >"$invalid"
invalid_before=$(cksum "$invalid")
if "$merge" "$invalid_dir" "$seed" 2>/dev/null; then
	echo "omp-settings-merge accepted invalid YAML" >&2
	exit 1
fi
test "$(cksum "$invalid")" = "$invalid_before"

# YAML false is a scalar, not an empty document, and must also remain intact.
false_root_dir=$tmp/false-root
false_root=$false_root_dir/config.yml
mkdir -p "$false_root_dir"
printf 'false\n' >"$false_root"
false_root_before=$(cksum "$false_root")
if "$merge" "$false_root_dir" "$seed" 2>/dev/null; then
	echo "omp-settings-merge accepted a false YAML document root" >&2
	exit 1
fi
test "$(cksum "$false_root")" = "$false_root_before"
