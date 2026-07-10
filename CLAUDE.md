# Rules

## Nix

- Evaluate: `./x.sh nix-eval-home`
- Build: `./x.sh nix-build-home`
- Activate: `./x.sh nix-switch-home`
- Format: `./x.sh fmt` (all file types via treefmt)
- Lint: `./x.sh lint` (Nix via statix/deadnix, shell via shellcheck, Python via basedpyright)
