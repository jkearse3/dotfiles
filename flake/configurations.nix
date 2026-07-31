{
  config,
  inputs,
  lib,
  withSystem,
  ...
}:
let
  inherit (lib) mkOption types;

  userType = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "User account name";
      };
      homeDirectory = mkOption {
        type = types.strMatching "^/.*";
        description = "Absolute user home directory";
      };
    };
  };

  homeType = types.submodule {
    options = {
      stateVersion = mkOption {
        type = types.str;
        description = "Home Manager state version";
      };
      module = mkOption {
        type = types.deferredModule;
        description = "Home Manager module composed by this blueprint";
      };
    };
  };

  darwinType = types.submodule {
    options = {
      stateVersion = mkOption {
        type = types.ints.unsigned;
        description = "nix-darwin state version";
      };
      module = mkOption {
        type = types.deferredModule;
        description = "nix-darwin module composed by this blueprint";
      };
    };
  };

  blueprintType = types.submodule {
    options = {
      system = mkOption {
        type = types.enum [ "aarch64-darwin" ];
        description = "Nix platform supported by this blueprint";
      };
      user = mkOption {
        type = userType;
        description = "Primary user identity";
      };
      home = mkOption {
        type = homeType;
        description = "Home Manager configuration";
      };
      darwin = mkOption {
        type = darwinType;
        description = "nix-darwin configuration";
      };
    };
  };

  validateBlueprintIds =
    blueprints:
    let
      invalidIds = lib.filter (blueprintId: builtins.match "^[a-z0-9][a-z0-9-]*$" blueprintId == null) (
        builtins.attrNames blueprints
      );
    in
    if invalidIds == [ ] then
      blueprints
    else
      throw "Invalid blueprint IDs: ${lib.concatStringsSep ", " invalidIds}";

  normalizedBlueprints = lib.mapAttrs (blueprintId: blueprint: {
    inherit blueprintId;
    inherit (blueprint)
      system
      user
      home
      darwin
      ;
    os = "darwin";
    homeConfiguration = "${blueprint.user.name}@${blueprintId}";
    systemConfiguration = blueprintId;
  }) config.dotfiles.blueprints;

  mkHomeConfiguration = import ./mkHomeConfiguration.nix {
    inherit inputs withSystem;
  };
  mkDarwinConfiguration = import ./mkDarwinConfiguration.nix {
    inherit inputs withSystem;
  };
in
{
  options = {
    dotfiles.blueprints = mkOption {
      type = types.attrsOf blueprintType;
      default = { };
      apply = validateBlueprintIds;
      description = "Complete Home Manager and nix-darwin configuration recipes";
    };

    flake = {
      homeConfigurations = mkOption {
        type = types.lazyAttrsOf types.raw;
        default = { };
        description = "Home Manager configurations by user@blueprint ID";
      };
      darwinConfigurations = mkOption {
        type = types.lazyAttrsOf types.raw;
        default = { };
        description = "Darwin configurations by blueprint ID";
      };
      blueprints = mkOption {
        type = types.attrsOf types.raw;
        default = { };
        description = "Blueprint metadata used to select canonical flake outputs";
      };
    };
  };

  config.flake = {
    homeConfigurations = lib.mapAttrs' (
      _: blueprint: lib.nameValuePair blueprint.homeConfiguration (mkHomeConfiguration blueprint)
    ) normalizedBlueprints;

    darwinConfigurations = lib.mapAttrs' (
      _: blueprint: lib.nameValuePair blueprint.systemConfiguration (mkDarwinConfiguration blueprint)
    ) normalizedBlueprints;

    blueprints = lib.mapAttrs (_: blueprint: {
      inherit (blueprint)
        homeConfiguration
        os
        system
        systemConfiguration
        ;
      username = blueprint.user.name;
    }) normalizedBlueprints;
  };
}
