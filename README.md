# dotfiles

Configurations managed with Nix.

## Installation

1. Install Nix via [Determinate Nix](https://determinate.systems/nix-installer/).
2. Install [Homebrew](https://brew.sh/) (macOS).
3. Clone into `~/dotfiles` (as out-of-store symlinks assume this path).
4. Run `./x.sh nix-switch-system` to build and activate system config.
5. Run `./x.sh nix-switch-home` to build and activate home config.

## Usage

- `./x.sh nix-<cmd>-home` — home-manager: eval/build/diff/activate/switch
- `./x.sh nix-<cmd>-system` — system (selects darwin vs nixos per `uname -s`):
  eval/build/diff/activate/switch
- `./x.sh fmt` — format all files
- `./x.sh fmt-check` — check formatting without modifying files

## Reference

- [Direnv in linked worktrees](packages/direnv-worktree/README.md)
- [Nix cheatsheet](docs/cheatsheets/nix.md)
