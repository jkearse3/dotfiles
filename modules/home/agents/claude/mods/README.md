# Claude Code mods

Each child folder is one mod: a Claude Code plugin whose behavior is a module of
function hooks. The `claude` and `nono-claude` wrappers load every folder here
that holds `.claude-plugin/plugin.json` through `CLAUDE_CODE_PLUGIN_DIRS`, so a
new mod takes effect at the next launch without a Home Manager switch. With
editable delivery, `~/.claude/mods` links to this directory.

A mod's layout:

```
<mod-name>/
  .claude-plugin/plugin.json   { "name": "<mod-name>", "version": "0.1.0", "description": "..." }
  hooks/hooks.json             { "modules": ["./register.tsx"] }
  hooks/register.tsx           export const register: Register = (on, options) => { ... }
  hooks/*.test.ts              tests run by `claude plugin test`
  types/index.d.ts             only for a mod that keeps `$.state`; named by "types" in plugin.json
  tsconfig.json                { "extends": "./.claude-plugin/types/tsconfig.json" }
```

No `package.json` is needed. Claude Code compiles the module itself and writes
the API declarations into `.claude-plugin/types/` at every load; that folder is
ignored.

## Reloading

An interactive session reloads a mod when a file it already loads is saved.
After renaming the module or pointing `hooks.json` at another file, run
`/reload-plugins`. A new mod folder needs a restart, because the wrapper lists
the folders at launch.

## Checking

- `claude plugin validate <folder>` reports what the module hooks and calls and
  anything Claude Code would refuse.
- `tsc -p <folder>` type-checks the mod once it has loaded at least once.
- `claude plugin test <folder>` runs the tests. Through the `claude` wrapper it
  refuses to start, because the wrapper puts `--settings` before `plugin`; run
  it through the unwrapped binary instead.

The `plugin-authoring` skill carries the API reference and examples.
