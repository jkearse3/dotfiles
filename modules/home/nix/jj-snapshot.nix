# Puts the `nix-jj-snapshot` wrapper, which snapshots the Jujutsu working copy
# before running Nix, ahead of the real Nix on PATH, so every `nix` command run
# from inside a jj repository sees files created since the last jj command.
#
# The wrapper lives alone in `jjSnapshotNixBin`, a directory whose path stays
# the same across generations, so shells that started before an activation run
# the new wrapper. Two mechanisms keep that directory ahead of
# /nix/var/nix/profiles/default/bin, where the Determinate installer puts Nix:
#
# - `home.sessionPath` prepends it in the first fish, zsh, or bash shell of a
#   session, after the installer's and nix-darwin's shell hooks have added the
#   Nix profiles. Nested shells inherit that PATH: the hooks, and Home
#   Manager's session variables, skip themselves once an exported marker such
#   as `__HM_SESS_VARS_SOURCED` is set, so zsh and bash keep the order.
# - fish rebuilds PATH from `fish_user_paths` in every shell, and on this
#   machine the universal `fish_user_paths` lists the Nix profiles, so a nested
#   fish (a terminal multiplexer pane, for example) would move the real Nix back
#   in front. `programs.fish.shellInit` runs in every fish after that rebuild and
#   moves the directory back to the front of PATH.
#
# Agents' bash inherits PATH from the shell that launched them.
{
  config,
  dotfilesPackages,
  lib,
  ...
}:
let
  jjSnapshotNixBin = "${config.xdg.dataHome}/nix-jj-snapshot/bin";
in
{
  xdg.dataFile."nix-jj-snapshot/bin/nix".source = lib.getExe dotfilesPackages.nix-jj-snapshot;

  home.sessionPath = [ jjSnapshotNixBin ];

  programs.fish.shellInit = # fish
    ''
      set --global --export PATH ${lib.escapeShellArg jjSnapshotNixBin} (string match --invert -- ${lib.escapeShellArg jjSnapshotNixBin} $PATH)
    '';
}
