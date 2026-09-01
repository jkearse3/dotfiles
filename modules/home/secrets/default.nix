{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Logical secret environments are declared here rather than accepted as
  # free-form keys, so a misspelled consumer reference fails evaluation instead
  # of silently launching without secrets. Each name maps to a same-named
  # `[scopes.<name>]` in the repository-root secretspec.toml registry.
  options.secrets.environments = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [
      "opencode"
      "omp"
      "pi"
    ];
    description = ''
      Logical secret environment names available to
      `mkSecretEnvironmentWrapper`. Each corresponds to a `[scopes.<name>]`
      entry in the repository-root `secretspec.toml`. No provider or secret
      value is configured here: the concrete provider is machine-local state
      mapped to the `dotfiles` alias.
    '';
  };

  config = {
    # SecretSpec's manifest schema, scopes, optional secrets, and global provider
    # aliases are all relied on by the wrapper; reject older releases early.
    assertions = [
      {
        assertion = lib.versionAtLeast pkgs.secretspec.version "0.18.0";
        message = "secretspec ${pkgs.secretspec.version} is older than the required 0.18.0 for the dotfiles secret wrappers";
      }
    ];

    # Consumers name a logical environment only; the SecretSpec backend stays
    # behind this helper so replacing it does not touch any consuming module.
    _module.args.mkSecretEnvironmentWrapper = import ./mkSecretEnvironmentWrapper.nix {
      inherit lib pkgs;
      environments = config.secrets.environments;
      manifest = ../../../secretspec.toml;
    };

    # `pkgs.devenv` bundles its own older `secretspec` binary, so raise this one's
    # install priority to win the profile collision and keep the interactive
    # `secretspec` at the version the wrappers require.
    home.packages = [
      (lib.hiPrio pkgs.secretspec)
      pkgs._1password-cli
    ];
  };
}
