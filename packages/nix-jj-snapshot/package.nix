# A `nix` executable that snapshots the Jujutsu working copy before running
# `realNix` with the same arguments; see `nix-jj-snapshot.sh`. The home
# configuration puts it ahead of the real Nix on PATH
# (`modules/home/nix/jj-snapshot.nix`). `realNix` defaults to the Nix that the
# Determinate installer puts in the default profile; the behavior test builds
# an instance that runs a stub instead.
{
  pkgs,
  realNix ? "/nix/var/nix/profiles/default/bin/nix",
}:
pkgs.writeShellApplication {
  name = "nix";
  # The store path is named after the wrapper rather than `nix`, so generation
  # diffs do not confuse it with Nix itself.
  derivationArgs.name = "nix-jj-snapshot";
  # `jj` comes from the user's PATH, so the snapshot uses the jj version and
  # configuration that manage the repository.
  text = ''
    REAL_NIX=${pkgs.lib.escapeShellArg realNix}
  ''
  + builtins.readFile ./nix-jj-snapshot.sh;
}
