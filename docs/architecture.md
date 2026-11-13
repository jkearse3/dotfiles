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
`modules/`. Nothing outside `flake/` is a flake-parts module: `packages/`,
`overlays/`, and `blueprints/` hold plain functions that their `flake/` module
calls, and `modules/` holds Home Manager and nix-darwin modules.
`flake/nixpkgs.nix` supplies shared per-system package arguments to the
development shell and configuration constructors. `flake/blueprints/default.nix`
calls `blueprints/`, defines the blueprint schema, validates blueprint IDs,
derives output names, and exports the selector inventory. Its private Home and
Darwin constructors, `home-configuration.nix` and `darwin-configuration.nix`,
sit beside it. The constructors select packages, inject identity and state
versions, apply required configuration baselines, and import the blueprint
modules. Workstation policy belongs in modules.

`flake/checks.nix` registers the standalone tests that `nix flake check` runs. A
test runs inside the derivation that delivers what it tests, such as a package
build or a module derivation the home configuration builds. A test that nothing
builds runs as an explicitly registered flake check instead. Repository packages
are also registered as checks, because the home build does not necessarily build
every package. A check that only runs a script with some tools is defined in
`flake/checks.nix`; a check that needs more lives in its own `check.nix` next to
its tests, such as `modules/home/neovim/nvim/tests/check.nix`, and
`flake/checks.nix` registers it with `callPackage`, as `flake/packages.nix`
registers `packages/*/package.nix`.

Lint runs as flake checks too, so `nix flake check` gates it. `lint-nix`,
`lint-shell`, and `lint-python` run statix and deadnix, shellcheck, and Pyrefly
in the sandbox over the files in the flake source; untracked files are not
linted. The `lint` package depends on those checks and `pi-extensions-checked`,
so `nix build --no-link .#lint` is the fast subset that builds only lint.

## Commands

Read-only work uses plain Nix commands from the repository root: `nix fmt`,
`nix flake check`, and `nix build` of the `lint` and `eval-blueprints` packages.
The imperative workflows are flake apps run with `nix run .#<app> -- [options]`,
described under [Blueprint Outputs](#blueprint-outputs). No repository script
adds flags to these commands, so the binary cache comes from the user's Nix
configuration (the Nix home module copies `nixConfig` from `flake.nix`), and a
plain command reads a local `dotfiles-private` checkout only when given
`--override-input dotfiles-private path:<checkout>`. The `nix` wrapper below
only snapshots the working copy; it passes arguments through unchanged.

## Working-Copy Snapshots

In a colocated jj repository, Nix reads a flake through Git and sees only the
files in the Git index, which jj updates when it snapshots the working copy, so
a file created since the last jj command is missing from a flake evaluation. The
home configuration therefore puts a `nix` wrapper (`packages/nix-jj-snapshot`)
ahead of the real Nix on `PATH`; it runs `jj util snapshot` in the current
directory's repository, then the real Nix with the same arguments. Run `nix`
from inside the repository whose flake it reads: a flake reference to another
checkout is not snapshotted.

Jujutsu signs every commit it writes, including working-copy snapshots, so a
snapshot can ask 1Password for approval (see `docs/ssh.md`). When the snapshot
fails, for example while 1Password is locked, the wrapper stops before running
Nix; `NIX_SKIP_JJ_SNAPSHOT=1` skips the snapshot. The wrapper's script describes
when it skips the snapshot on its own, and `modules/home/nix/jj-snapshot.nix`
how it stays first on `PATH`. Where the wrapper does not run, such as before the
first Home Manager activation, `jj status` snapshots by hand.

## Blueprint Outputs

The canonical `.#blueprints` inventory maps each blueprint ID to its platform,
user, Home output name, and Darwin output name. The flake apps use this
inventory for explicit `--blueprint` selection and for the managed
`dotfiles/blueprint-id` marker. A blueprint ID is configuration identity, not a
hostname or physical-device identity.

Home Manager and nix-darwin remain separate outputs. They can be evaluated,
built, and activated independently; no constructor embeds Home Manager into
nix-darwin. The `eval-blueprints` package records the derivation paths of every
blueprint's Home Manager and nix-darwin configuration without depending on them,
so `nix build --no-link .#eval-blueprints` evaluates every blueprint without
building one, and fails when any of them fails to evaluate.

The `build-home`, `switch-home`, `build-system`, and `switch-system` flake apps
(`flake/apps.nix`) build or activate one blueprint's configuration through nh,
for example `nix run .#build-home -- --blueprint <blueprint-id>`. They run the
`dotfiles-apps` script (`packages/dotfiles-apps`), which carries the inventory
from build time, selects the blueprint from `--blueprint` or the marker, and
adds the `DOTFILES_PRIVATE_LOCAL` override to its nh calls. `switch-home` and
`switch-system` also refuse to run from a linked Git worktree or secondary jj
workspace, naming the main checkout, because activation installs that checkout's
files for every session; `--allow-worktree` overrides this.

The same script backs the `package-update` and `flake-update` apps.
`package-update` runs every `packages/*/update.sh --latest` updater (`--dry-run`
prints the new pins without editing files). `flake-update`
(`packages/dotfiles-apps/flake-update.sh`) updates `flake.lock` and runs the
updaters in a jj change of its own, described `build(nix): update dependencies`.
When anything changed, it builds `eval-blueprints`, runs `nix flake check`, and
builds the Home Manager and nix-darwin configurations of the blueprint the
marker selects, then commits the change with jj.

The commit description lists the flake inputs whose revisions moved, the package
pins whose versions changed, and the package versions that differ from the
configurations built from the parent revision, across the whole closures of what
the blueprint installs, so packages behind unversioned wrappers count too. Each
line names only the versions a package lost and gained, packages that moved
together share a line, and the heading names the blueprint's Nix system in place
of the target-triple suffix some toolchain components carry. `flake-update`
formats and validates it with `commit-message`. Each phase of a run starts with
a `==>` line, and a successful run ends with
`==> Committed the dependency update as <change-id>`.

When a check fails, `flake-update` exits 1 and leaves the update uncommitted in
`@`. Fix the failure there and run it again: seeing a non-empty `@` with the
update's subject, it reruns the checks without updating again and commits the
fix in the same change. An explanation of the fix written into the description
of `@` with `jj describe` stays above the generated lists. `jj abandon @`
discards the update instead. It also refuses to commit when `@` changed while
the checks ran. When `nix flake update` or an updater fails, it restores `@` to
its parent instead, so no partial update remains.

`nix flake update` runs without the `DOTFILES_PRIVATE_LOCAL` override, which it
would otherwise write into `flake.lock`; only the checks build against the local
checkout.

## Module Interfaces

Reusable Home modules receive `dotfilesPackages`, which combines repository
packages with selected external packages. `dotfilesNixConfig` is the `nixConfig`
that `flake.nix` declares, which the Nix module copies into the user's Nix
configuration.

Modules that contribute agent skills import `modules/home/agents/skills.nix`
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

## Home Migrations

A home migration rewrites user state that an older configuration or tool left
behind, such as a deprecated key in files the configuration does not own. It
lives beside the module whose state it migrates, as a `home.activation.migrate*`
step after `writeBoundary` that runs its command through `run`, so a dry run
only prints it. The command is safe to rerun on every switch: it changes only
files still in the old shape and prints one line per file it changes. A comment
on the step states when to delete it. The command's fixture test runs in the
derivation the activation step runs, which is also registered as a flake check,
as `modules/home/vcs/jj/migrate-jj-sign-on-push` is. Migrations keep no ledger
of applied migrations and no order between them.

## Extension Rules

Add a package implementation under `packages/` and register it explicitly in
`flake/packages.nix`. Add an override of an upstream package as an overlay under
`overlays/` and list it explicitly in `flake/nixpkgs.nix`. Add a standalone test
that no derivation builds by registering it explicitly in `flake/checks.nix`;
when the check needs more than running a script with some tools, define it in a
`check.nix` next to its tests and register that file there. Add reusable policy
under the appropriate `modules/` subtree, then import it explicitly from a
blueprint composition. Add a migration of user state as a
[home migration](#home-migrations) in the module that owns that state. Add a
blueprint as another typed declaration in `blueprints/default.nix`. Add flake
integration as a flake-parts module under `flake/` and import it explicitly from
`flake.nix`; `flake.nix` imports no repository file outside `flake/`. Do not
derive blueprints from hostnames or discover modules from the filesystem.
