# The shell every agent frontend runs model-issued commands in. Frontends
# otherwise pick one on their own — Claude Code and OpenCode fall back to zsh
# when the login shell is fish, and pi hardcodes `/bin/bash`, which is bash 3.2
# on macOS — so one session's commands can fail in another.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.agents.shellPath = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    default = "${config.home.profileDirectory}/bin/bash";
    description = ''
      Absolute path of the bash that agent frontends run shell commands in.

      It points into the home profile rather than the Nix store so frontends
      that persist it in their own mutable settings, such as pi, keep a path
      that survives garbage collection across generations.
    '';
  };

  config.home.packages = [
    pkgs.bashInteractive
  ];
}
