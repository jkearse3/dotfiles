{
  config,
  lib,
  pkgs,
  ...
}:
let
  # macOS's tmp_cleaner deletes /tmp files untouched for 3 days, which orphans
  # long-running devenv process stacks whose bookkeeping lives under
  # `$XDG_RUNTIME_DIR/devenv-<hash>` and otherwise falls back to /tmp
  # (cachix/devenv#3316). Keep the path short: macOS caps Unix socket paths at
  # 104 characters. The path is absolute because launchd does not expand
  # `$HOME`.
  runtimeDirectory = "${config.home.homeDirectory}/.run";

  # Home Manager's session variables are skipped when a parent process exported
  # `__HM_SESS_VARS_SOURCED` before the variable existed (e.g. a long-running
  # herdr server), so each shell also sets it outside that guard. An inherited
  # non-empty value is left alone.
  posixRuntimeDirectoryFallback = ''
    if [ -z "''${XDG_RUNTIME_DIR-}" ]; then export XDG_RUNTIME_DIR="${runtimeDirectory}"; fi
  '';
  fishRuntimeDirectoryFallback = ''
    if test -z "$XDG_RUNTIME_DIR"; set -gx XDG_RUNTIME_DIR "${runtimeDirectory}"; end
  '';
in
lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
  home = {
    sessionVariables.XDG_RUNTIME_DIR = runtimeDirectory;
    activation.runtimeDirectory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -m 700 -p "${runtimeDirectory}"
      run chmod 700 "${runtimeDirectory}"
    '';
  };

  programs = {
    fish.shellInit = fishRuntimeDirectoryFallback;
    zsh.envExtra = posixRuntimeDirectoryFallback;
    bash = {
      profileExtra = posixRuntimeDirectoryFallback;
      bashrcExtra = posixRuntimeDirectoryFallback;
    };
  };

  # Apps that launchd starts in the GUI session (Ghostty, Conductor, and the
  # processes they spawn before any shell runs) never read shell configuration,
  # so this login agent exports the variable into the session's launchd
  # environment. Only apps launched after it runs inherit it: running apps need
  # a relaunch, and apps macOS restores at login can start before it. It does not create the
  # directory; activation does. Skipping the Nix store wait runs it through a
  # launcher named after the agent, so Login Items shows that name rather than
  # "sh"; if launchd starts it before the store is mounted, the failed start is
  # retried until it succeeds.
  launchd.agents.xdg-runtime-dir = {
    enable = true;
    waitForNixStore = false;
    config = {
      ProgramArguments = [
        "/bin/launchctl"
        "setenv"
        "XDG_RUNTIME_DIR"
        runtimeDirectory
      ];
      RunAtLoad = true;
      KeepAlive.SuccessfulExit = false;
    };
  };
}
