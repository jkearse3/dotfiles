# Rules

## Nix

- Routine commands select the blueprint from
  `$XDG_CONFIG_HOME/dotfiles/blueprint-id`, defaulting the config root to
  `~/.config`; do not pass `--blueprint` when that marker exists.
- Evaluate: `./x.sh nix-eval-home`
- Evaluate all blueprints: `./x.sh nix-eval-all`
- Build: `./x.sh nix-build-home`
- Activate: `./x.sh nix-switch-home`
- Format: `./x.sh fmt` (all file types via treefmt)
- Lint: `./x.sh lint` (Nix via statix/deadnix, tracked `.sh` and `.bash` files
  via shellcheck, Python via basedpyright)

If a blueprint-dependent command reports that no blueprint is selected, run
`./x.sh nix-blueprints` to discover the configured blueprint IDs, ask the user
which blueprint to apply to this device, then bootstrap with
`./x.sh nix-switch-home --blueprint <blueprint-id>`. Home Manager creates the
marker, so subsequent commands do not need `--blueprint`. Never infer the
blueprint from the hostname, username, or hardware.
