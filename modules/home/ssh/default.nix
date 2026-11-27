{
  config,
  lib,
  pkgs,
  ...
}:
let
  homeDirectory = config.home.homeDirectory;
  cfg = config.dotfiles.onePasswordSsh;
  gitKeyHandle = config.dotfiles.gitKey.handle;
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
  };

  # `bootstrap/git-key.sh` installs the handle of this Mac's Secure Enclave git
  # key here, with its `.pub` beside it; the handle is the file OpenSSH uses to
  # reach the key and holds no private key. The script runs before Home Manager
  # exists, so it writes the same path itself; the `git-key-bootstrap` check
  # keeps the two equal.
  options.dotfiles.gitKey.handle = mkInternalPathOption "${homeDirectory}/.ssh/git_secure_enclave" "Handle of this Mac's Secure Enclave git key";

  config = {
    home = {
      sessionVariables.SSH_AUTH_SOCK = cfg.normalizedSocket;

      # GitHub SSH and commit signing have no fallback, so a switch made before
      # the script ran would leave git failing. This runs before Home Manager
      # writes anything, so a refused switch changes nothing.
      activation.checkGitKeyHandle = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
        if [ ! -f ${lib.escapeShellArg gitKeyHandle} ] || [ ! -f ${lib.escapeShellArg "${gitKeyHandle}.pub"} ]; then
          errorEcho "No Secure Enclave git key handle at ${gitKeyHandle}; nothing was changed. Run bootstrap/git-key.sh, add the key on GitHub, then switch again (see docs/ssh.md)."
          exit 1
        fi
      '';

      file.${normalizedSocketTarget} = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        source = config.lib.file.mkOutOfStoreSymlink cfg.darwinSocket;
      };
    };

    programs.ssh = {
      enable = true;
      package = null;
      enableDefaultConfig = false;
      settings = {
        # GitHub uses this Mac's Secure Enclave key only. `IdentityAgent none`
        # keeps ssh from contacting 1Password at all, so a locked or quit
        # 1Password cannot delay or prompt a GitHub connection.
        "github.com" = {
          HostName = "github.com";
          User = "git";
          IdentityFile = gitKeyHandle;
          IdentitiesOnly = true;
          IdentityAgent = "none";
          SecurityKeyProvider = "/usr/lib/ssh-keychain.dylib";
        };
        "*".IdentityAgent = cfg.normalizedSocket;
      };
    };
  };
}
