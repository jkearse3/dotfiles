{
  config,
  dotfilesUser,
  lib,
  ...
}:
let
  # environment.shells renders a package as this stable profile path, which
  # also lands in /etc/shells, so the login shell survives fish updates.
  fishLoginShell = "/run/current-system/sw/bin/fish";
in
{
  programs.fish.enable = true;

  # chsh(1) accepts only shells listed in /etc/shells.
  environment.shells = [ config.programs.fish.package ];

  # nix-darwin sets users.users.<name>.shell only for users.knownUsers, which
  # requires pinning a uid, and the same account can have a different uid on
  # each machine. Set the login shell by name instead. It runs after the etc
  # step has listed fish in /etc/shells, and leaves the account untouched when
  # it already uses fish.
  system.activationScripts.postActivation.text = ''
    name=${lib.escapeShellArg dotfilesUser.name}
    shell=${lib.escapeShellArg fishLoginShell}
    if ! current=$(/usr/bin/dscl . -read "/Users/$name" UserShell); then
      echo "login-shell: cannot read the login shell of $name" >&2
      exit 1
    fi
    if [ "''${current#UserShell: }" != "$shell" ]; then
      echo "setting login shell of $name to $shell..." >&2
      /usr/bin/dscl . -create "/Users/$name" UserShell "$shell"
    fi
  '';
}
