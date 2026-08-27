// Reject pi extension imports that pi cannot resolve at runtime.
//
// Pi loads extensions through jiti with a fixed module table: the bundled
// `VIRTUAL_MODULES` when pi runs as a Bun single-file executable, and the
// equivalent `getAliases()` map otherwise (both in
// `dist/core/extensions/loader.js`). Anything outside that table falls through
// to ordinary node resolution from the extension's own directory.
//
// That fallback is a trap here. Editable delivery points `~/.pi/agent/extensions`
// at the checkout, where the devshell links a declaration-only `node_modules`
// built from pi's `.d.ts` files. A new dependency would therefore typecheck
// cleanly and then fail at load with a module-resolution error, which reads
// like a broken install rather than a missing dependency.
//
// So the manifest is the contract: extensions import node builtins, the
// modules pi bundles, each other, and packages declared in the shared root
// `dependencies`. Development-only packages never become runtime imports.
//
// Specifiers come from TypeScript's own parser rather than a pattern match,
// because a pattern match reads one line at a time and prettier wraps a long
// `import(...)` across two. The parse walks declarations directly rather than
// using `preProcessFile`, which reports `export * from` but not
// `export * as ns from`.
//
// usage: NODE_PATH=<dir containing typescript> node extension-imports-check.mjs <extensions-dir>

import { readdirSync, readFileSync } from "node:fs";
import { builtinModules } from "node:module";
import path from "node:path";
import { createRequire } from "node:module";

let ts;
try {
  ts = createRequire(import.meta.filename)("typescript");
} catch {
  console.error(
    "extension-imports-check: cannot resolve typescript; set NODE_PATH to the directory holding it",
  );
  process.exit(2);
}

// Mirrors the pi module table named above, minus the `@mariozechner/*` aliases
// it also carries. Those are the pre-rename spellings, kept upstream so older
// extensions keep loading; new source here should use the current names.
const PI_MODULES = [
  "@earendil-works/pi-agent-core",
  "@earendil-works/pi-ai",
  "@earendil-works/pi-ai/compat",
  "@earendil-works/pi-ai/oauth",
  "@earendil-works/pi-ai/providers/all",
  "@earendil-works/pi-coding-agent",
  "@earendil-works/pi-tui",
  "@sinclair/typebox",
  "@sinclair/typebox/compile",
  "@sinclair/typebox/value",
  "typebox",
  "typebox/compile",
  "typebox/value",
];

// Both spellings resolve: jiti hands an unaliased specifier to node, which
// accepts a builtin with or without the prefix.
const allowed = new Set([
  ...PI_MODULES,
  ...builtinModules,
  ...builtinModules.map((name) => `node:${name}`),
]);

// Extensions are plain `.ts` so that one `tsc` run covers every source. Pi would
// happily load a `.js` extension, and `tsconfig.json` globs `**/*.ts`, which
// matches neither `.js` nor the `.mts`/`.cts`/`.tsx` spellings; any of those
// would be checked by nothing at all, so reject them here rather than let them
// through unexamined.
const SOURCE_EXTENSION = ".ts";
const REJECTED_EXTENSIONS = [
  ".js",
  ".mjs",
  ".cjs",
  ".jsx",
  ".mts",
  ".cts",
  ".tsx",
];

function collect(dir, found = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === "node_modules" || entry.name === ".pi-types") continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      collect(full, found);
    } else if (entry.isFile()) {
      found.push(full);
    }
  }
  return found;
}

const [, , extensionsDir] = process.argv;
if (!extensionsDir) {
  console.error("usage: extension-imports-check.mjs <extensions-dir>");
  process.exit(2);
}

let manifest;
try {
  manifest = JSON.parse(
    readFileSync(path.join(extensionsDir, "package.json"), "utf8"),
  );
} catch (error) {
  console.error(
    `extension-imports-check: cannot read ${extensionsDir}/package.json: ${error}`,
  );
  process.exit(2);
}

const runtimePackageNames = new Set(Object.keys(manifest.dependencies ?? {}));
const runtimePackageName = (specifier) => {
  const parts = specifier.split("/");
  return specifier.startsWith("@") ? parts.slice(0, 2).join("/") : parts[0];
};

const files = collect(extensionsDir);
const sources = files.filter((file) => file.endsWith(SOURCE_EXTENSION));
const problems = [];

for (const file of files) {
  const extension = path.extname(file);
  if (REJECTED_EXTENSIONS.includes(extension)) {
    problems.push(`${file}: extensions must be ${SOURCE_EXTENSION} sources`);
  }
}

// An empty match would make this check silently vacuous.
if (sources.length === 0) {
  for (const problem of problems) console.error(problem);
  console.error(
    `extension-imports-check: no ${SOURCE_EXTENSION} sources under ${extensionsDir}`,
  );
  process.exit(1);
}

// Every syntactic form that names a module: static imports and re-exports,
// `import x = require(...)`, and `import(...)`/`require(...)` calls anywhere in
// the tree. A specifier built at runtime is undecidable and is left alone.
function specifiersIn(source) {
  const found = [];
  const record = (node) => {
    if (
      node &&
      (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node))
    ) {
      found.push(node.text);
    }
  };

  const visit = (node) => {
    if (ts.isImportDeclaration(node) || ts.isExportDeclaration(node)) {
      record(node.moduleSpecifier);
    } else if (
      ts.isImportEqualsDeclaration(node) &&
      ts.isExternalModuleReference(node.moduleReference)
    ) {
      record(node.moduleReference.expression);
    } else if (ts.isCallExpression(node)) {
      const callee = node.expression;
      const isRequire = ts.isIdentifier(callee) && callee.text === "require";
      const isImport = callee.kind === ts.SyntaxKind.ImportKeyword;
      if (isRequire || isImport) record(node.arguments[0]);
    }
    ts.forEachChild(node, visit);
  };

  ts.forEachChild(source, visit);
  return found;
}

for (const file of sources) {
  const source = ts.createSourceFile(
    file,
    readFileSync(file, "utf8"),
    ts.ScriptTarget.Latest,
    true,
  );
  for (const specifier of specifiersIn(source)) {
    // Relative imports resolve against the extension itself.
    if (specifier.startsWith(".")) continue;
    if (allowed.has(specifier)) continue;
    if (runtimePackageNames.has(runtimePackageName(specifier))) continue;
    problems.push(
      `${file}: import "${specifier}" is not resolvable by pi at runtime`,
    );
  }
}

if (problems.length > 0) {
  for (const problem of problems) console.error(problem);
  console.error("");
  console.error(
    "Extensions may import node builtins, the modules pi bundles, each other, and declared runtime dependencies.",
  );
  console.error(
    "See the header of extension-imports-check.mjs before changing the allowlist.",
  );
  process.exit(1);
}

console.log(`extension-imports-check: ${sources.length} source(s) OK`);
