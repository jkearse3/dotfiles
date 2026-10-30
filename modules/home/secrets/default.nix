{ lib, pkgs, ... }:
{
  # SecretSpec's manifest schema, scopes, optional secrets, and global provider
  # aliases are all relied on by the wrapper; reject older releases early.
  assertions = [
    {
      assertion = lib.versionAtLeast pkgs.secretspec.version "0.18.0";
      message = "secretspec ${pkgs.secretspec.version} is older than the required 0.18.0 for the dotfiles secret wrappers";
    }
  ];

  # The manifest alone declares valid consumer scopes and provider requirements.
  # Consumers name a scope; machine-local state selects the concrete provider.
  _module.args.mkSecretEnvironmentWrapper = import ./mkSecretEnvironmentWrapper.nix {
    inherit lib pkgs;
    manifest = ../../../secretspec.toml;
  };

  # `pkgs.devenv` bundles its own older `secretspec` binary, so raise this one's
  # install priority to win the profile collision and keep the interactive
  # `secretspec` at the version the wrappers require.
  home.packages = [
    (lib.hiPrio pkgs.secretspec)
    pkgs._1password-cli
  ];
}
