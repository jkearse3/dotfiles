# Architecture

The repository composes configuration in one direction:

```text
packages -> modules -> blueprints -> flake outputs
```

## Layers

`packages/` contains derivation implementations. `flake/packages.nix` registers
those derivations against the stable package set and constructs the shared
unstable package set used by development shells and output constructors. Its
overlays affect only that unstable boundary.

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

`flake/` contains flake-parts integration and output constructors. `flake.nix`
assembles these modules, while `flake/packages.nix` supplies shared per-system
package arguments to the development shell and configuration constructors.
`flake/blueprint-outputs.nix` defines the blueprint schema, validates blueprint
IDs, derives output names, and exports the selector inventory. The Home and
Darwin constructors select packages, inject identity and state versions, apply
required configuration baselines, and import the blueprint modules. Workstation
policy belongs in modules.

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
`flake/packages.nix`. Add reusable policy under the appropriate `modules/`
subtree, then import it explicitly from a blueprint composition. Add a blueprint
as another typed declaration in `blueprints/default.nix`; do not derive
blueprints from hostnames or discover modules from the filesystem.
