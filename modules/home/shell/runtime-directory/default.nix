{
  lib,
  pkgs,
  ...
}:
let
  # macOS's tmp_cleaner deletes /tmp files untouched for 3 days, which orphans
  # long-running devenv process stacks whose bookkeeping lives under
  # `$XDG_RUNTIME_DIR/devenv-<hash>` and otherwise falls back to /tmp
  # (cachix/devenv#3316). Keep the path short: macOS caps Unix socket paths at
  # 104 characters.
  runtimeDirectory = "$HOME/.run";
in
{
  home = {
    sessionVariables = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      XDG_RUNTIME_DIR = runtimeDirectory;
    };
    activation.runtimeDirectory = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run mkdir -m 700 -p "${runtimeDirectory}"
        run chmod 700 "${runtimeDirectory}"
      ''
    );
  };
}
