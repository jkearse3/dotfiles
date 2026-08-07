#!/usr/bin/env bash

# Format Claude Code settings files in place.
# Reproduces Claude Code's own serialization (two-space indent, one array
# element per line) so treefmt and Claude agree on the file. Key order is
# preserved deliberately: Claude writes keys in schema declaration order, and
# reordering them here would churn on the next settings write.

# Slurping rejects anything that is not exactly one JSON object. An emptied or
# half-pasted settings.json otherwise formats to something Claude Code cannot
# parse while the run still exits 0.
require_one_object='if length == 1 and (.[0] | type == "object") then .[0] else error("expected a single JSON object") end'

for file in "$@"; do
	formatted=$(jq -s --indent 2 "$require_one_object" "$file")

	# treefmt decides a file changed by comparing size and mtime around the
	# format step, so an unconditional rewrite can report an untouched file as
	# changed and trip --fail-on-change. Compare the bytes this would write,
	# including the trailing newline that command substitution strips.
	printf '%s\n' "$formatted" | cmp -s - "$file" || printf '%s\n' "$formatted" >"$file"
done
