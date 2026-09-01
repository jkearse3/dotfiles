# Pi extensions

This directory is the source for Pi's standard global extension path:

```text
~/.pi/agent/extensions
```

In editable Home Manager mode that path is a symlink into this checkout. Pi
auto-discovers `*/index.ts`, and `/reload` applies source changes without a Home
Manager rebuild.

## Create an extension

Use a directory with an `index.ts` entry point and keep helpers and fixtures
beside it:

```text
extensions/
└── example/
    ├── index.ts
    ├── helper.ts
    └── helper.test.ts
```

All extension sources must be TypeScript. The repository checks imports, runs
`tsc`, and executes every `*.test.ts` fixture.

## Herdr lifecycle integration

`herdr-agent-state.ts` is intentionally a relative symlink to the official Pi
integration in the active Nix profile. This gives Herdr its canonical installed
filename, so `herdr integration status` verifies the same artifact shipped by
the installed Herdr package instead of a copied extension.

Editable delivery preserves that profile-relative link. Locked delivery replaces
it with a direct link to the selected `dotfilesPackages.herdr` artifact, and the
Home Manager build checks the integration identity, version marker, and source
link target. Do not run `herdr integration install pi`; Home Manager owns the
canonical path.

## Add a runtime dependency

All global extensions share this directory's npm dependency set. From any
working directory, install through Pi's canonical path:

```bash
npm install --prefix ~/.pi/agent/extensions <package>
```

npm saves an exact version, updates `package-lock.json`, and writes the
Git-ignored `node_modules`. Install scripts are disabled by `.npmrc`; review a
package before making any exception for generated or native artifacts.

After switching revisions or on a fresh editable checkout, restore exactly the
locked dependency tree:

```bash
npm ci --prefix ~/.pi/agent/extensions
```

Only packages in `dependencies` are importable by extension source. Nix rebuilds
the same lockfile independently for checks and locked Home Manager delivery, so
local `node_modules` is never trusted as release input.
