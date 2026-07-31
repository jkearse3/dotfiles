{
  lib,
  inputs,
  withSystem,
  ...
}:
let
  blueprints = {
    laptop-personal = {
      os = "darwin";
      system = "aarch64-darwin";
      username = "johnnie";
      extraHomeModules = [
        {
          agents.opencode.sopsEnvironmentFile = ../../secrets/personal/opencode.sops.yaml;
        }
      ];
      extraSystemModules = [ ];
    };
    laptop-lab = {
      os = "darwin";
      system = "aarch64-darwin";
      username = "johnnie";
      extraHomeModules = [ ];
      extraSystemModules = [ ];
    };
  };

  mkBlueprint =
    blueprintId: blueprint:
    let
      args = blueprint // {
        inherit blueprintId;
      };
    in
    {
      imports = [
        ((import ./mkDarwin.nix { inherit inputs withSystem; }) args)
        ((import ./mkHome.nix { inherit inputs withSystem; }) args)
      ];
    };
in
{
  imports = lib.mapAttrsToList mkBlueprint blueprints;

  options.flake = {
    homeConfigurations = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.raw;
      default = { };
      description = "Home Manager configurations by user@blueprint ID";
    };

    darwinConfigurations = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.raw;
      default = { };
      description = "Darwin configurations by blueprint ID";
    };

    blueprints = lib.mkOption {
      type = lib.types.attrsOf lib.types.raw;
      default = { };
      description = "Blueprint metadata used to select canonical flake outputs";
    };
  };

  config.flake.blueprints = lib.mapAttrs (blueprintId: blueprint: {
    inherit (blueprint) os system username;
    homeConfiguration = "${blueprint.username}@${blueprintId}";
    systemConfiguration = blueprintId;
  }) blueprints;
}
