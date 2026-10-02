# Claude Code mods

Each child folder is one mod: a Claude Code plugin whose behavior is a module of
function hooks. The `claude` and `nono-claude` wrappers load every folder here
that holds `.claude-plugin/plugin.json` through `CLAUDE_CODE_PLUGIN_DIRS`, so a
new mod takes effect at the next launch without a Home Manager switch. With
editable delivery, `~/.claude/mods` links to this directory and an interactive
session reloads a mod whenever one of its files is saved.

A mod's layout:

```
<mod-name>/
  .claude-plugin/plugin.json   { "name": "<mod-name>", "version": "0.1.0", "description": "..." }
  hooks/hooks.json             { "modules": ["./register.tsx"] }
  hooks/register.tsx           export const register: Register = (on, options) => { ... }
```

Check a mod with `claude plugin validate <folder>`,
`claude plugin test <folder>`, and, once it has loaded, `tsc -p <folder>`. The
`plugin-authoring` skill carries the API reference and examples.
