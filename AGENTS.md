# Rules

## Nix

Run every command from the repository root.

- Routine commands select the blueprint from
  `$XDG_CONFIG_HOME/dotfiles/blueprint-id`, defaulting the config root to
  `~/.config`; do not pass `--blueprint` when that marker exists.
- Evaluate all blueprints: `nix build --no-link .#eval-blueprints`
- Build: `nix run .#build-home` (`nix run .#build-system` for nix-darwin)
- Activate: `nix run .#switch-home` (only from the main checkout; in a linked
  worktree or secondary jj workspace it refuses, and `--allow-worktree`
  overrides this only when the user asks to activate that checkout)
- Update dependencies: `nix run .#flake-update`, following the `flake-update`
  skill (`packages/dotfiles-apps/skills/flake-update`), which covers fixing and
  explaining what an update breaks
- Format: `nix fmt` (all file types via treefmt)
- Check (standalone tests, formatting, and lint): `nix flake check`
- Lint: `nix build --no-link .#lint` (builds only the lint flake checks and pi
  extension checks: Nix via statix/deadnix, tracked `.sh` and `.bash` files via
  shellcheck, Python via Pyrefly (`all` preset))

If a blueprint-dependent command reports that no blueprint is selected, run
`nix eval .#blueprints --apply builtins.attrNames` to discover the configured
blueprint IDs, ask the user which blueprint to apply to this device, then
bootstrap with `nix run .#switch-home -- --blueprint <blueprint-id>`. Home
Manager creates the marker, so subsequent commands do not need `--blueprint`.
Never infer the blueprint from the hostname, username, or hardware.

The `nix` on `PATH` is a wrapper that runs `jj util snapshot` first, because Nix
reads this flake through Git and sees a new file only after a snapshot. Run
`nix` from inside this repository. If a command misses a new file because the
wrapper is not installed yet, run `jj status` and retry. When the snapshot fails
because 1Password is locked, `nix` stops; set `NIX_SKIP_JJ_SNAPSHOT=1` only when
evaluating without new files is acceptable.

The apps apply `DOTFILES_PRIVATE_LOCAL` (`1`, `true`, or `yes` for
`~/dotfiles-private`, or a checkout path); plain `nix` commands need
`--override-input dotfiles-private path:<checkout>` instead.

## Workflow Tooling

This repository defines the user's agent workflow and the tools it runs on. The
workflow must stay composable and able to evolve piece by piece, so that losing
or replacing one tool never takes a large part of the workflow with it. When
proposing, adopting, or wiring a tool into it:

- Keep workflow state in open, plain formats readable without the tool, such as
  Markdown, Mermaid, JSON, or files in the repository.
- Depend on a tool only through a narrow seam, such as one command name or a
  documented format, so that replacing the tool changes only the seam's
  implementation.
- Make each tool optional to the flow: when it fails or is removed, the flow
  falls back to a less convenient path instead of stopping.
- Prefer small single-purpose tools over platforms that bundle storage,
  integrations, and UI, and state the lock-in cost when proposing one that does.
- Pin every tool in Nix through this flake, so the same lock always yields the
  same tool. A prebuilt upstream release fetched by hash qualifies; an install
  script, a global package manager, or anything fetched unpinned does not.
