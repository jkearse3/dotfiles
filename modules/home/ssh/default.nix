{
  config,
  lib,
  pkgs,
  ...
}:
let
  homeDirectory = config.home.homeDirectory;
  cfg = config.dotfiles.onePasswordSsh;
  normalizedSocketTarget = lib.removePrefix "${homeDirectory}/" cfg.normalizedSocket;
  mkInternalPathOption =
    default: description:
    lib.mkOption {
      type = lib.types.nonEmptyStr;
      inherit default description;
      internal = true;
      readOnly = true;
    };
in
{
  options.dotfiles.onePasswordSsh = {
    normalizedSocket = mkInternalPathOption "${homeDirectory}/.1password/agent.sock" "Normalized 1Password SSH agent socket";
    darwinSocket = mkInternalPathOption "${homeDirectory}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock" "Native Darwin 1Password SSH agent socket";
    githubAuthenticationSelector = mkInternalPathOption "${homeDirectory}/.ssh/github_personal_authentication.pub" "GitHub authentication public-key selector";
    githubSigningSelector = mkInternalPathOption "${homeDirectory}/.ssh/github_personal_signing.pub" "GitHub signing public-key selector";
  };

  config = {
    home.sessionVariables.SSH_AUTH_SOCK = cfg.normalizedSocket;

    home.file.${normalizedSocketTarget} = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      source = config.lib.file.mkOutOfStoreSymlink cfg.darwinSocket;
    };

    programs.ssh = {
      enable = true;
      package = null;
      enableDefaultConfig = false;
      settings = {
        "github.com" = {
          HostName = "github.com";
          User = "git";
          IdentityFile = cfg.githubAuthenticationSelector;
          IdentitiesOnly = true;
        };
        "*".IdentityAgent = cfg.normalizedSocket;
      };
    };
  };
}
