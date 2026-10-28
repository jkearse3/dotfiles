{
  dotfilesUser,
  lib,
  pkgs,
  ...
}:
let
  # macOS's tmp_cleaner deletes /tmp files untouched for 3 days and dirhelper
  # does the same under `$TMPDIR`, which orphans long-running processes such as
  # devenv process stacks whose bookkeeping lives under
  # `$XDG_RUNTIME_DIR/devenv-<hash>` and otherwise falls back to /tmp
  # (cachix/devenv#3316). launchd's dirs_cleaner empties /var/run at every boot
  # and nothing prunes it during uptime, so the nix-darwin configuration creates
  # this directory there, mirroring Linux's tmpfs /run/user/$UID. Keep the path
  # short: macOS caps Unix socket paths at 104 characters. The directory is
  # named after the uid, which is looked up when used because the same account
  # can have a different uid on each machine.
  inherit (dotfilesUser) runtimeDirectoryParent;
  posixRuntimeDirectory = "${runtimeDirectoryParent}/$(/usr/bin/id -u)";

  # The variable is exported only once the system has created the directory
  # for this user, so a Home Manager switch before the nix-darwin one, or a
  # login before the boot daemon has run, leaves programs on their own
  # fallbacks instead of pointing them at a missing or foreign directory.
  posixIsRuntimeDirectoryReady =
    directory: ''[ -d "${directory}" ] && [ ! -L "${directory}" ] && [ -O "${directory}" ]'';

  # Each shell sets the variable itself rather than through Home Manager's
  # session variables, whose guard is skipped when a parent process exported
  # `__HM_SESS_VARS_SOURCED` before the variable existed (e.g. a long-running
  # herdr server). An inherited non-empty value is left alone.
  posixRuntimeDirectoryFallback = ''
    if [ -z "''${XDG_RUNTIME_DIR-}" ]; then
      xdg_runtime_dir="${posixRuntimeDirectory}"
      if ${posixIsRuntimeDirectoryReady "$xdg_runtime_dir"}; then export XDG_RUNTIME_DIR="$xdg_runtime_dir"; fi
      unset xdg_runtime_dir
    fi
  '';
  fishRuntimeDirectoryFallback = ''
    if test -z "$XDG_RUNTIME_DIR"
      set -l xdg_runtime_dir "${runtimeDirectoryParent}/"(/usr/bin/id -u)
      if test -d "$xdg_runtime_dir"; and not test -L "$xdg_runtime_dir"; and test -O "$xdg_runtime_dir"
        set -gx XDG_RUNTIME_DIR "$xdg_runtime_dir"
      end
    end
  '';
in
lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
  # Only the system can create the directory, so activation warns rather than
  # fails when it is missing.
  home.activation.runtimeDirectory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    xdg_runtime_dir="${posixRuntimeDirectory}"
    if ! { ${posixIsRuntimeDirectoryReady "$xdg_runtime_dir"}; }; then
      warnEcho "$xdg_runtime_dir is not a directory owned by $(/usr/bin/id -un), so XDG_RUNTIME_DIR stays unset; run ./x.sh nix-switch-system to create it"
    fi
    unset xdg_runtime_dir
  '';

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
  # a relaunch, and apps macOS restores at login can start before it. Skipping
  # the Nix store wait runs it through a launcher named after the agent, so
  # Login Items shows that name rather than "sh". launchd does not guarantee
  # that the system's boot daemon runs before login, so a failed start is
  # retried until the directory exists and is owned by the user, which also
  # covers a Home Manager switch made before the nix-darwin one.
  launchd.agents.xdg-runtime-dir = {
    enable = true;
    waitForNixStore = false;
    config = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''dir="${posixRuntimeDirectory}" && ${posixIsRuntimeDirectoryReady "$dir"} && exec /bin/launchctl setenv XDG_RUNTIME_DIR "$dir"''
      ];
      RunAtLoad = true;
      KeepAlive.SuccessfulExit = false;
    };
  };
}
