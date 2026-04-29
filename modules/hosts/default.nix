{
  lib,
  config,
  ...
}:
{
  imports = [
    ./mbp-hf-2
    ./mbp-personal
  ];

  options.flake.homeConfigurations = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = { };
    description = "Home-manager configurations by user@hostname";
  };

  options.flake.darwinConfigurations = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = { };
    description = "Darwin configurations by hostname";
  };

  options.flake.hostOs = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.enum [
        "darwin"
        "nixos"
      ]
    );
    default = { };
    description = "OS class (darwin/nixos) for each declared host, derived from the *Configurations namespaces";
  };

  config.flake.hostOs =
    lib.mapAttrs (_: _: "darwin") config.flake.darwinConfigurations
    // lib.mapAttrs (_: _: "nixos") config.flake.nixosConfigurations;
}
