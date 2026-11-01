{
  dotfilesNixConfig,
  dotfilesPackages,
  lib,
  pkgs,
  ...
}:
{
  # The nix-index-database overlay wraps nix-locate and comma with a prebuilt
  # database, so neither needs a local `nix-index` run or a cache symlink.
  home.packages = [
    dotfilesPackages.nix-cleanup
    pkgs.comma-with-db
    pkgs.deadnix
    pkgs.devenv
    pkgs.nix-index-with-db
    pkgs.nix-output-monitor
    pkgs.nixd
    pkgs.nixfmt
    pkgs.nvd
    pkgs.statix
  ];

  # `dotfilesNixConfig` is the flake's `nixConfig`, which Nix offers only to
  # commands that pass `--accept-flake-config`; copying its binary cache here
  # lets plain `nix` commands use it too. The cache lives in the user-level
  # config because the Nix daemon honors user substituters for trusted users,
  # and /etc/nix/nix.custom.conf belongs to the Determinate Nix installer.
  # Writing the file directly avoids Home Manager's `nix.settings`, which
  # requires `nix.package` even though the installer, not Home Manager,
  # provides Nix.
  xdg.configFile."nix/nix.conf".text = ''
    extra-substituters = ${lib.concatStringsSep " " dotfilesNixConfig.extra-substituters}
    extra-trusted-public-keys = ${lib.concatStringsSep " " dotfilesNixConfig.extra-trusted-public-keys}
  '';
}
