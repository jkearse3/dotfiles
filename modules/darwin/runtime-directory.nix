{ dotfilesUser, lib, ... }:
let
  inherit (dotfilesUser) runtimeDirectoryParent;

  # launchd's dirs_cleaner empties /var/run at every boot and nothing prunes it
  # during uptime, so a directory there is ephemeral like Linux's tmpfs
  # /run/user/$UID. /var/run is writable only by root, so the system creates
  # the user's directory. It is named after the uid looked up on this machine,
  # since the same account can have a different uid on each machine. The
  # script refuses a symlink or a non-directory rather than chown whatever is
  # there. It calls macOS's own tools by absolute path so it needs neither the
  # Nix store nor a PATH. This module only creates the directory; it does not
  # set XDG_RUNTIME_DIR.
  prepareRuntimeDirectory = ''
    # Each `mkdir -p` creates at most its last level, which `-m` covers; `-p`
    # lets the boot daemon and activation run concurrently.
    # shellcheck disable=SC2174
    set -eu
    name=${lib.escapeShellArg dotfilesUser.name}
    parent=${lib.escapeShellArg runtimeDirectoryParent}
    uid=$(/usr/bin/id -u "$name")
    gid=$(/usr/bin/id -g "$name")
    dir="$parent/$uid"

    /bin/mkdir -p -m 755 "$parent"
    if [ -L "$parent" ] || [ ! -d "$parent" ] || [ "$(/usr/bin/stat -f %u "$parent")" != 0 ]; then
      echo "xdg-runtime-dir: $parent is not a directory owned by root" >&2
      exit 1
    fi

    if [ -L "$dir" ] || { [ -e "$dir" ] && [ ! -d "$dir" ]; }; then
      echo "xdg-runtime-dir: $dir exists and is not a directory" >&2
      exit 1
    fi
    /bin/mkdir -p -m 700 "$dir"
    /usr/sbin/chown "$uid:$gid" "$dir"
    /bin/chmod 700 "$dir"
  '';
in
{
  # Recreates the directory after each boot empties /var/run. Setting
  # ProgramArguments directly, rather than `script` or `command`, avoids
  # nix-darwin's wait for the Nix store. A failed start is retried until it
  # succeeds. launchd does not order system daemons before login, so the
  # directory can appear after the user's session has started.
  launchd.daemons.xdg-runtime-dir.serviceConfig = {
    ProgramArguments = [
      "/bin/sh"
      "-c"
      prepareRuntimeDirectory
    ];
    RunAtLoad = true;
    KeepAlive.SuccessfulExit = false;
  };

  # Creates the directory as soon as the configuration is activated, without
  # waiting for a reboot. It runs early, before activation changes anything
  # else, so a refusal stops activation instead of leaving it half applied.
  system.activationScripts.extraActivation.text = ''
    /bin/sh -c ${lib.escapeShellArg prepareRuntimeDirectory}
  '';
}
