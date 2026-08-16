# dotfiles

Configurations managed with Nix.

## Installation

Follow the [fresh Darwin installation guide](docs/installation.md). The flake
has a private SSH input, so a new machine must commission 1Password and verify
access to `dotfiles-private` before the first `nix develop` invocation.

After installing the prerequisites and initializing the colocated Jujutsu
workspace, the activation sequence is:

```sh
nix develop --accept-flake-config --command ./x.sh nix-blueprints
nix develop --accept-flake-config --command ./x.sh nix-switch-system --blueprint <blueprint-id>
nix develop --accept-flake-config --command ./x.sh nix-switch-home --blueprint <blueprint-id>
```

Home Manager creates `dotfiles/blueprint-id` under the XDG config root (normally
`~/.config`), so later commands can invoke `./x.sh` directly without
`--blueprint`.

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
- [Installation](docs/installation.md)
- [Secrets](docs/secrets.md)
- [SSH and commit signing](docs/ssh.md)
- [Direnv in linked worktrees](packages/direnv-worktree/README.md)
- [Nix cheatsheet](docs/cheatsheets/nix.md)
