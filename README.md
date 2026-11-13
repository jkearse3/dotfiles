# dotfiles

Configurations managed with Nix.

## Installation

Follow the [fresh Darwin installation guide](docs/installation.md). The flake
has a private SSH input, so a new machine must commission 1Password and verify
access to `dotfiles-private` before the first `nix run` or `nix develop`
invocation.

After installing the prerequisites and initializing the colocated Jujutsu
workspace, the activation sequence is:

```sh
nix eval --accept-flake-config .#blueprints --apply builtins.attrNames
nix run --accept-flake-config .#switch-system -- --blueprint <blueprint-id>
nix run --accept-flake-config .#switch-home -- --blueprint <blueprint-id>
```

`--accept-flake-config` enables the binary cache declared in `flake.nix` until
Home Manager writes it into the user's Nix configuration. Home Manager also
creates `dotfiles/blueprint-id` under the XDG config root (normally
`~/.config`), so later commands do not need `--blueprint`.

## Usage

Run these from the repository root:

- `nix run .#<build|switch>-home -- [--blueprint <blueprint-id>]` - Home
  Manager: build or switch
- `nix run .#<build|switch>-system -- [--blueprint <blueprint-id>]` - system:
  build or switch
- `nix build --no-link .#eval-blueprints` - evaluate every blueprint without
  building it
- `nix eval .#blueprints --apply builtins.attrNames` - list configured blueprint
  IDs
- `nix fmt` - format all files
- `nix build --no-link .#checks.aarch64-darwin.treefmt` - check formatting
  without modifying files
- `nix build --no-link .#lint` - check Nix, tracked `.sh` and `.bash` files, and
  Python; a fast subset of `nix flake check`, which runs the same lint checks
- `nix run .#package-update -- [--dry-run]` - update the pins of packaged tools
- `nix run .#flake-update` - update `flake.lock` and the package pins, then
  evaluate every blueprint, run `nix flake check`, and build the marker-selected
  blueprint's Home Manager and nix-darwin configurations, committing the result
  with jj only when every check passes; after a failure, fix it in `@` and run
  it again to resume

Build and switch apps use an explicit `--blueprint` first, then the Home
Manager-managed blueprint marker. They run nh, which shows a package diff
against the configuration in use and leaves no result link in the checkout;
build never activates. The `nix` that Home Manager puts on `PATH` snapshots the
Jujutsu working copy first, so Nix sees new files; see
[Working-Copy Snapshots](docs/architecture.md#working-copy-snapshots).

## Reference

- [Architecture](docs/architecture.md)
- [Installation](docs/installation.md)
- [Secrets](docs/secrets.md)
- [SSH and commit signing](docs/ssh.md)
- [Direnv in linked worktrees](packages/direnv-worktree/README.md)
- [Copying local files into worktrees](packages/worktree-include/README.md)
- [Nix cheatsheet](docs/cheatsheets/nix.md)
