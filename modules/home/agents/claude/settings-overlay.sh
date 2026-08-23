#!/usr/bin/env bash

# Resolve the `--settings` payload for one Claude Code launch.
#
# `default.nix` records the layering this rests on: the payload outranks
# `~/.claude/settings.json`, and Claude Code resolves per leaf. Deleting a
# scalar leaf from the payload therefore hands exactly that leaf back to the
# machine-local file, where `/model` and `/config` persist what they change, and
# leaves its siblings pinned. A leaf kept in the payload keeps its pinned value
# and shadows the machine-local one.
#
# Only the dot-joined paths named on the command line are eligible, and only
# where the pinned value at that path is a scalar. An array or an object is
# never deleted: a machine can already add to a pinned array and can already
# replace individual leaves under a pinned object, whereas deleting the object
# would surrender every leaf beneath it at once. `permissions.defaultMode` is
# never named, so it reaches Claude Code as pinned.
#
# usage: claude-settings-overlay <pinned> <machine> [overridable-path...]
#
# Prints the effective settings JSON on stdout. A missing or unusable
# machine-local file yields the pinned settings unchanged rather than an error,
# so a half-written local file never blocks a launch.

if [ "$#" -lt 2 ]; then
	echo "claude-settings-overlay: usage: claude-settings-overlay <pinned> <machine> [overridable-path...]" >&2
	exit 2
fi

pinned=$1
machine=$2
shift 2

if [ ! -r "$machine" ]; then
	cat "$pinned"
	exit 0
fi

# `--slurpfile` rejects a malformed machine-local file outright. It reads an
# empty one as `[]` and a top-level `null` or `false` as itself, both of which
# `// {}` absorbs as "overrides nothing" — the quiet path, since a half-written
# file is a normal transient state. Any other non-object is a file that needs
# attention, so `error` sends it to the noisy fallback below. `jq` writes its
# own diagnostic to stderr on the way there, which names the syntax error or the
# offending type far better than the fallback's one-liner can.
#
# `defines` asks the parent object whether it `has` the final key rather than
# testing `getpath(...) != null`, because a leaf the machine deliberately sets
# to `false` or `null` still has to count as defined and hand its pinned value
# over. The `try` covers every way the walk can fail rather than just an
# untraversable parent: an empty path reaches `has(null)`, which raises rather
# than answering, and a path nothing defines is exactly what `false` means here.
if overlaid=$(
	jq -c --slurpfile machine "$machine" '
    def defines($root; $path):
      try ($root | getpath($path[:-1]) | type == "object" and has($path[-1]))
      catch false;

    . as $pinned
    | (($machine[0] // {}) | if type == "object" then . else error("machine-local settings are a \(type), not an object") end) as $overrides
    | delpaths([
        $ARGS.positional[]
        | split(".") as $path
        | select(defines($overrides; $path))
        | select(defines($pinned; $path))
        | select($pinned | getpath($path) | type | . != "object" and . != "array")
        | $path
      ])
  ' "$pinned" --args "$@"
); then
	printf '%s\n' "$overlaid"
else
	echo "claude-settings-overlay: ignoring unusable $machine" >&2
	cat "$pinned"
fi
