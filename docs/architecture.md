# Architecture

The repository composes configuration in one direction:

```text
packages -> modules -> blueprints -> flake outputs
```

## Layers

`packages/` contains derivation implementations. `flake/packages.nix` registers
those derivations against the stable package set. `flake/nixpkgs.nix` constructs
the shared unstable package set used by development shells and output
constructors.

`overlays/` contains nixpkgs overlays that patch or override upstream packages.
`flake/nixpkgs.nix` applies them to the shared unstable package set only, not
the stable one.

`modules/home/` and `modules/darwin/` contain reusable Home Manager and
nix-darwin modules. Importing a feature module normally activates that feature.
Modules use concrete package and source interfaces supplied by the flake layer;
they do not inspect flake inputs, blueprint IDs, or blueprint declarations.

`blueprints/default.nix` contains complete reusable configuration recipes. A
blueprint coordinates one Home Manager module and one nix-darwin module for a
typed platform, user identity, and state versions. The current workstation
composition is local to this file, and both blueprints reuse it. The blueprints
form the laptop-dev family: `laptop-dev-default` is the development workstation
for any machine without work-specific tweaks, and `laptop-dev-work` is the same
workstation with them. No blueprint configures a secret provider, because
secrets resolve through machine-local SecretSpec state (see
[Secrets](secrets.md)). The work blueprint composes local private profile data
into repository-scoped Git and Jujutsu identities while retaining the shared
personal identity as its default.

`flake/` contains flake-parts integration. Of the repository's own files,
`flake.nix` imports only modules from `flake/`, each explicitly; those modules
wire in `packages/`, `overlays/`, and `blueprints/`, and blueprints import
`modules/`. `flake/nixpkgs.nix` supplies shared per-system package arguments to
the development shell and configuration constructors.
`flake/blueprints/default.nix` imports `blueprints/`, defines the blueprint
schema, validates blueprint IDs, derives output names, and exports the selector
inventory. Its private Home and Darwin constructors, `home-configuration.nix`
and `darwin-configuration.nix`, sit beside it. The constructors select packages,
inject identity and state versions, apply required configuration baselines, and
import the blueprint modules. Workstation policy belongs in modules.

`flake/checks.nix` registers the standalone tests that `./x.sh check` runs. A
test runs inside the derivation that delivers what it tests, such as a package
build or a module derivation the home configuration builds. A test that nothing
builds runs as an explicitly registered flake check instead. Repository packages
are also registered as checks, because the home build does not necessarily build
every package. A check that only runs a script with some tools is defined in
`flake/checks.nix`; a check that needs more lives in its own `check.nix` next to
its tests, such as `modules/home/neovim/nvim/tests/check.nix`, and
`flake/checks.nix` registers it with `callPackage`, as `flake/packages.nix`
registers `packages/*/package.nix`.

## Blueprint Outputs

The canonical `.#blueprints` inventory maps each blueprint ID to its platform,
user, Home output name, and Darwin output name. `x.sh` uses this inventory for
explicit `--blueprint` selection and for the managed `dotfiles/blueprint-id`
marker. A blueprint ID is configuration identity, not a hostname or
physical-device identity.

Home Manager and nix-darwin remain separate outputs. They can be evaluated,
built, and activated independently; no constructor embeds Home Manager into
nix-darwin.

## Module Interfaces

Reusable Home modules receive `dotfilesPackages`, which combines repository
packages with selected external packages, and `dotfilesSource`, which describes
the repository source and editable-delivery mode. `modules/home/lib/source.nix`
turns the latter into the shared `mkSource` helper.

Modules that contribute agent skills import the agent registry interface
explicitly. Agent frontends import the modules providing the factories they use:
nono for sandbox wrappers, secrets for secret-environment wrappers. These
dependencies do not rely on another aggregate import or import ordering.

`modules/home/secrets` owns secret resolution mechanics: it runs each consumer's
command under SecretSpec against the committed, value-free `secretspec.toml`
registry. Consuming modules name a logical secret environment only, which maps
to a same-named SecretSpec scope. The concrete provider is machine-local state
mapped to the `dotfiles` alias, so neither a consumer nor a blueprint changes
when the provider does. See [Secrets](secrets.md) for the full boundary and
commissioning workflow.

## Extension Rules

Add a package implementation under `packages/` and register it explicitly in
`flake/packages.nix`. Add an override of an upstream package as an overlay under
`overlays/` and list it explicitly in `flake/nixpkgs.nix`. Add a standalone test
that no derivation builds by registering it explicitly in `flake/checks.nix`;
when the check needs more than running a script with some tools, define it in a
`check.nix` next to its tests and register that file there. Add reusable policy
under the appropriate `modules/` subtree, then import it explicitly from a
blueprint composition. Add a blueprint as another typed declaration in
`blueprints/default.nix`. Add flake integration as a flake-parts module under
`flake/` and import it explicitly from `flake.nix`; `flake.nix` imports no
repository file outside `flake/`. Do not derive blueprints from hostnames or
discover modules from the filesystem.
