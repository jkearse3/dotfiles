# dotfiles

Configurations managed with Nix.

## Installation

1. Install Nix via
   [Determinate Nix](https://determinate.systems/nix-installer/).
2. Install [Homebrew](https://brew.sh/) (macOS).
3. Clone into `~/dotfiles` (as out-of-store symlinks assume this path).
4. Run `nix develop --command jj-ensure` to initialize the required colocated jj
   workspace.
5. Run `nix develop --command ./x.sh nix-blueprints` and choose the blueprint to
   apply. The development shell provides the complete bootstrap command
   environment.
6. Run
   `nix develop --command ./x.sh nix-switch-system --blueprint <blueprint-id>`
   to build and activate the system config.
7. Run `nix develop --command ./x.sh nix-switch-home --blueprint <blueprint-id>`
   to build and activate the home config. This creates `dotfiles/blueprint-id`
   under the XDG config root (normally `~/.config`), so later commands can
   invoke `./x.sh` directly without `--blueprint`.

## Usage

- `./x.sh nix-<cmd>-home [--blueprint <blueprint-id>]` - Home Manager:
  eval/build/diff/activate/switch
- `./x.sh nix-<cmd>-system [--blueprint <blueprint-id>]` - system:
  eval/build/diff/activate/switch
- `./x.sh nix-eval-all` - evaluate every canonical blueprint without a marker
- `./x.sh nix-blueprints` - list configured blueprint IDs
- `./x.sh fmt` - format all files
- `./x.sh fmt-check` - check formatting without modifying files
- `./x.sh lint` - check Nix, tracked `.sh` and `.bash` files, and Python

Blueprint-dependent evaluation, build, and switch commands use an explicit
`--blueprint` first, then the Home Manager-managed blueprint marker. Builds use
blueprint-specific `result-home-<blueprint-id>` and
`result-system-<blueprint-id>` links so activation cannot consume another
blueprint's result.

## Reference

- [Architecture](docs/architecture.md)
- [Secrets](docs/secrets.md)
- [Direnv in linked worktrees](packages/direnv-worktree/README.md)
- [Nix cheatsheet](docs/cheatsheets/nix.md)
