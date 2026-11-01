# Rules

## Nix

Run every command from the repository root.

- Routine commands select the blueprint from
  `$XDG_CONFIG_HOME/dotfiles/blueprint-id`, defaulting the config root to
  `~/.config`; do not pass `--blueprint` when that marker exists.
- Evaluate all blueprints: `nix build --no-link .#eval-blueprints`
- Build: `nix run .#build-home` (`nix run .#build-system` for nix-darwin)
- Activate: `nix run .#switch-home`
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
