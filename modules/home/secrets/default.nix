{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Environments are declared here rather than accepted as free-form keys, so a
  # misspelled blueprint assignment fails evaluation instead of silently
  # launching its command without secrets.
  options.secrets.sops.environmentFiles = lib.mkOption {
    type = lib.types.submodule {
      options.opencode = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = lib.literalExpression "../secrets/personal/opencode.sops.yaml";
        description = "Secret environment shared by the OpenCode launchers.";
      };
    };
    default = { };
    description = ''
      SOPS-encrypted YAML file per logical secret environment. A file's
      top-level values become environment variables for commands built with
      `mkSecretEnvironmentWrapper` for that environment; a null entry runs its
      command with nothing injected.
    '';
  };

  config = {
    # Consumers name a logical environment only; the backend stays behind this
    # helper so replacing it does not touch any consuming module.
    _module.args.mkSecretEnvironmentWrapper = import ./mkSecretEnvironmentWrapper.nix {
      inherit lib pkgs;
      environmentFiles = config.secrets.sops.environmentFiles;
    };

    home.packages = [
      pkgs.age
      pkgs.sops
    ];
  };
}
