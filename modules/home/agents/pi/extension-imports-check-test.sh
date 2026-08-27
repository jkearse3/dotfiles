#!/usr/bin/env bash

# Fixtures for extension-imports-check. The checker's whole job is to catch an
# import before it reaches a pi that cannot resolve it, so a gap here is a gap
# that only shows up as a load failure on someone's machine.
#
# usage: extension-imports-check-test <path-to-extension-imports-check.mjs>

set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "usage: extension-imports-check-test <path-to-extension-imports-check.mjs>" >&2
	exit 2
fi

checker=$1
failures=0

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

# Each case writes one extension tree and asserts the checker's exit status,
# plus the specifier it is expected to name.
check() {
	local name=$1 expected=$2 wanted=${3-} manifest=${4-'{"dependencies":{}}'}
	local root="$work/case-$((++case_number))"
	mkdir -p "$root/an-extension"
	printf '%s\n' "$manifest" >"$root/package.json"
	cat >"$root/an-extension/index.ts"
	local output status=0
	output=$(node "$checker" "$root" 2>&1) || status=$?
	if [[ $status -ne $expected ]]; then
		echo "FAIL $name: expected exit $expected, got $status" >&2
		echo "$output" >&2
		failures=1
		return
	fi
	if [[ -n $wanted && $output != *"$wanted"* ]]; then
		echo "FAIL $name: output did not mention '$wanted'" >&2
		echo "$output" >&2
		failures=1
	fi
}

case_number=0

check "the imports the extensions actually use are allowed" 0 <<'EOF'
import { spawn } from "node:child_process";
import { StringEnum } from "@earendil-works/pi-ai";
import { Type } from "typebox";
import { defineTool } from "@earendil-works/pi-coding-agent";
import { Container } from "@earendil-works/pi-tui";
import { helper } from "./helper.ts";
export type { Thing } from "./helper.ts";
EOF

# Jiti hands an unaliased specifier to node, which takes a builtin either way.
check "a builtin without the node: prefix is allowed" 0 <<'EOF'
import { readFileSync } from "fs";
import * as path from "path";
EOF

check "a bare dependency is rejected" 1 "zod" <<'EOF'
import { z } from "zod";
EOF

check "a declared dependency is allowed" 0 "" '{"dependencies":{"zod":"1.2.3"}}' <<'EOF'
import { z } from "zod";
EOF

check "a declared dependency subpath is allowed" 0 "" '{"dependencies":{"yaml":"1.2.3"}}' <<'EOF'
import { parse } from "yaml/parse-cst";
EOF

check "a declared scoped dependency is allowed" 0 "" '{"dependencies":{"@example/tools":"1.2.3"}}' <<'EOF'
import { tool } from "@example/tools/runtime";
EOF

check "a development-only dependency is rejected" 1 "zod" '{"dependencies":{},"devDependencies":{"zod":"1.2.3"}}' <<'EOF'
import { z } from "zod";
EOF

# Prettier wraps any import call whose line runs long, which is what defeats
# reading the source one line at a time.
check "a dynamic import split across lines is rejected" 1 "yaml" <<'EOF'
const parser = await import(
  "yaml"
);
EOF

check "a require call is rejected" 1 "lodash" <<'EOF'
const lodash = require("lodash");
EOF

# A no-substitution template literal is as statically resolvable as a quoted
# string, while one carrying an expression remains undecidable.
check "a template-literal dynamic import is rejected" 1 "yaml" <<'EOF'
const parser = await import(`yaml`);
EOF

check "a template-literal require call is rejected" 1 "lodash" <<'EOF'
const lodash = require(`lodash`);
EOF

check "a re-export is rejected" 1 "chalk" <<'EOF'
export { red } from "chalk";
EOF

check "a star re-export is rejected" 1 "chalk" <<'EOF'
export * from "chalk";
EOF

# TypeScript's preprocessor reports every other re-export form but not this one,
# which is why the checker parses instead of preprocessing.
check "a namespaced star re-export is rejected" 1 "chalk" <<'EOF'
export * as Chalk from "chalk";
EOF

check "an import-equals require is rejected" 1 "lodash" <<'EOF'
import lodash = require("lodash");
EOF

# A specifier assembled at runtime cannot be decided either way.
check "a computed dynamic import is left alone" 0 <<'EOF'
const name = "ya" + "ml";
const parser = await import(name);
EOF

check "a specifier inside a comment or string is not an import" 0 <<'EOF'
// import { z } from "zod";
const sample = 'import { red } from "chalk";';
export const value = sample.length;
EOF

# Pi's table carries whole specifiers, not prefixes.
check "an unlisted subpath of a pi module is rejected" 1 "@earendil-works/pi-ai/nope" <<'EOF'
import { thing } from "@earendil-works/pi-ai/nope";
EOF

# The declaration-only tree makes a type-only import typecheck, so it has to be
# caught here or not at all.
check "a type-only import of a dependency is rejected" 1 "zod" <<'EOF'
import type { ZodType } from "zod";
EOF

# Pi still resolves these, but they are the pre-rename spellings.
check "a legacy @mariozechner alias is rejected" 1 "@mariozechner/pi-tui" <<'EOF'
import { Text } from "@mariozechner/pi-tui";
EOF

# Pi would load a plain .js extension that no typecheck ever sees, and the
# tsconfig glob matches neither .js nor the other TypeScript spellings, so a
# helper in any of them is invisible to every other check.
for rejected in js mjs cjs mts cts tsx; do
	rejected_root="$work/rejected-$rejected"
	mkdir -p "$rejected_root/an-extension"
	printf '{"dependencies":{}}\n' >"$rejected_root/package.json"
	echo 'import { defineTool } from "@earendil-works/pi-coding-agent";' \
		>"$rejected_root/an-extension/index.ts"
	echo 'export * from "zod";' >"$rejected_root/an-extension/helper.$rejected"
	if output=$(node "$checker" "$rejected_root" 2>&1); then
		echo "FAIL a .$rejected source is rejected: expected failure" >&2
		failures=1
	elif [[ $output != *"must be .ts sources"* ]]; then
		echo "FAIL a .$rejected source is rejected: wrong message" >&2
		echo "$output" >&2
		failures=1
	fi
done

# A nested helper is as loadable as the entry point.
nested_root="$work/nested"
mkdir -p "$nested_root/an-extension/helpers"
printf '{"dependencies":{}}\n' >"$nested_root/package.json"
echo 'import { helper } from "./helpers/helper.ts";' \
	>"$nested_root/an-extension/index.ts"
echo 'export * as YAML from "yaml";' \
	>"$nested_root/an-extension/helpers/helper.ts"
if output=$(node "$checker" "$nested_root" 2>&1); then
	echo "FAIL a nested source is scanned: expected failure" >&2
	failures=1
elif [[ $output != *"yaml"* ]]; then
	echo "FAIL a nested source is scanned: wrong message" >&2
	echo "$output" >&2
	failures=1
fi

# A tree the checker cannot see into would otherwise report success.
empty_root="$work/empty"
mkdir -p "$empty_root/an-extension"
printf '{"dependencies":{}}\n' >"$empty_root/package.json"
if node "$checker" "$empty_root" >/dev/null 2>&1; then
	echo "FAIL a tree with no sources is rejected: expected failure" >&2
	failures=1
fi

# The devshell links a declaration-only tree in beside the sources.
vendored_root="$work/vendored"
mkdir -p "$vendored_root/an-extension" "$vendored_root/node_modules/zod"
printf '{"dependencies":{}}\n' >"$vendored_root/package.json"
echo 'import { spawn } from "node:child_process";' \
	>"$vendored_root/an-extension/index.ts"
echo 'export declare const z: unknown;' >"$vendored_root/node_modules/zod/index.d.ts"
echo 'const z = require("zod");' >"$vendored_root/node_modules/zod/index.ts"
if ! node "$checker" "$vendored_root" >/dev/null 2>&1; then
	echo "FAIL node_modules is not scanned: expected success" >&2
	failures=1
fi

if [[ $failures -ne 0 ]]; then
	echo "extension-imports-check-test: failures" >&2
	exit 1
fi

echo "extension-imports-check-test: all cases passed"
