{
  config,
  lib,
  pkgs,
  ...
}:
let
  # macOS's tmp_cleaner deletes /tmp files untouched for 3 days and dirhelper
  # does the same under `$TMPDIR`, which orphans long-running processes such as
  # devenv process stacks whose bookkeeping lives under
  # `$XDG_RUNTIME_DIR/devenv-<hash>` and otherwise falls back to /tmp
  # (cachix/devenv#3316). Neither cleaner touches the home directory. This
  # mirrors Linux's /run/user/$UID inside the XDG `~/.local` tree. Keep the path
  # short: macOS caps Unix socket paths at 104 characters. The path is absolute
  # because launchd does not expand `$HOME`.
  runtimeDirectory = "${config.home.homeDirectory}/.local/run";

  # Unlike a tmpfs /run/user/$UID, the directory survives reboots, so the
  # first run after each boot deletes whatever was last modified before that
  # boot. Entries created since boot are kept, so the login agent cannot remove
  # a socket that a daemon started at login has already bound. Directories are
  # removed only once empty, so a socket created this boot keeps its parent.
  # Later runs in the same boot skip the cleanup because a process may have
  # reopened a lockfile from an earlier boot without changing its mtime.
  # Cleanup failures only warn, so the variable is still exported. The boot
  # time is converted in UTC so a boot in the repeated daylight saving hour
  # cannot shift the reference past it. It calls macOS's own tools by absolute
  # path so it behaves the same under activation, whose PATH puts GNU tools
  # first, and under launchd's minimal PATH.
  prepareRuntimeDirectory = pkgs.writeScript "prepare-xdg-runtime-dir" ''
    #!/bin/sh
    set -eu
    dir='${runtimeDirectory}'
    cleaned_boot_marker="$dir/.cleaned-boot"

    /bin/mkdir -p -m 700 "$dir"
    if [ -L "$dir" ] || [ ! -d "$dir" ] || [ ! -O "$dir" ]; then
      echo "prepare-xdg-runtime-dir: $dir is not a directory owned by $(/usr/bin/id -un)" >&2
      exit 1
    fi
    /bin/chmod 700 "$dir"

    boot_session=$(/usr/sbin/sysctl -n kern.bootsessionuuid)
    if [ "$(/bin/cat "$cleaned_boot_marker" 2>/dev/null || true)" = "$boot_session" ]; then
      exit 0
    fi

    remove_entries_from_earlier_boots() {
      boot_seconds=$(/usr/sbin/sysctl -n kern.boottime | /usr/bin/sed -E 's/^\{ sec = ([0-9]+),.*/\1/')
      case $boot_seconds in
      "" | *[!0-9]*) return 1 ;;
      esac
      boot_reference=$(/usr/bin/mktemp "''${TMPDIR:-/tmp}/xdg-runtime-boot.XXXXXX") || return
      trap '/bin/rm -f "$boot_reference"' EXIT
      TZ=UTC0 /usr/bin/touch -t "$(TZ=UTC0 /bin/date -r "$boot_seconds" +%Y%m%d%H%M.%S)" "$boot_reference" &&
        /usr/bin/find "$dir" -mindepth 1 ! -newer "$boot_reference" \( ! -type d -o -empty \) -delete
    }
    remove_entries_from_earlier_boots ||
      echo "prepare-xdg-runtime-dir: could not remove every entry left by an earlier boot from $dir" >&2
    printf '%s\n' "$boot_session" >"$cleaned_boot_marker"
  '';

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
      run ${prepareRuntimeDirectory}
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
  # a relaunch, and apps macOS restores at login can start before it. It also
  # prepares the directory at each login, which clears what the previous boot
  # left behind. Skipping the Nix store wait runs it through a launcher named
  # after the agent, so Login Items shows that name rather than "sh". A failed
  # start is retried until it succeeds, which covers launchd starting it before
  # the store is mounted; if the directory is a symlink or not owned by the
  # user, it keeps failing and the variable is not exported.
  launchd.agents.xdg-runtime-dir = {
    enable = true;
    waitForNixStore = false;
    config = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''${prepareRuntimeDirectory} && exec /bin/launchctl setenv XDG_RUNTIME_DIR "${runtimeDirectory}"''
      ];
      RunAtLoad = true;
      KeepAlive.SuccessfulExit = false;
    };
  };
}
