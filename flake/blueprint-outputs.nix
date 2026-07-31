# Defines the blueprint declaration interface and turns each declaration into
# Home Manager, nix-darwin, and selector-inventory flake outputs.
{
  config,
  inputs,
  lib,
  withSystem,
  ...
}:
let
  inherit (lib) mkOption types;

  userDeclarationType = types.submodule {
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

  homeDeclarationType = types.submodule {
    options = {
      stateVersion = mkOption {
        type = types.str;
        description = "Home Manager state version";
      };
      module = mkOption {
        type = types.deferredModule;
        description = "Unevaluated Home Manager composition selected by this blueprint";
      };
    };
  };

  darwinDeclarationType = types.submodule {
    options = {
      stateVersion = mkOption {
        type = types.ints.unsigned;
        description = "nix-darwin state version";
      };
      module = mkOption {
        type = types.deferredModule;
        description = "Unevaluated nix-darwin composition selected by this blueprint";
      };
    };
  };

  blueprintDeclarationType = types.submodule {
    options = {
      system = mkOption {
        type = types.enum [ "aarch64-darwin" ];
        description = "Nix platform supported by this blueprint";
      };
      user = mkOption {
        type = userDeclarationType;
        description = "Primary user identity";
      };
      home = mkOption {
        type = homeDeclarationType;
        description = "Home Manager configuration";
      };
      darwin = mkOption {
        type = darwinDeclarationType;
        description = "nix-darwin configuration";
      };
    };
  };

  validateBlueprintIds =
    blueprintDeclarations:
    let
      invalidIds = lib.filter (blueprintId: builtins.match "^[a-z0-9][a-z0-9-]*$" blueprintId == null) (
        builtins.attrNames blueprintDeclarations
      );
    in
    if invalidIds == [ ] then
      blueprintDeclarations
    else
      throw "Invalid blueprint IDs: ${lib.concatStringsSep ", " invalidIds}";

  blueprintOutputSpecs = lib.mapAttrs (blueprintId: blueprint: {
    inherit blueprintId;
    inherit (blueprint)
      system
      user
      home
      darwin
      ;
    os = "darwin";
    homeConfigurationName = "${blueprint.user.name}@${blueprintId}";
    darwinConfigurationName = blueprintId;
  }) config.dotfiles.blueprintDeclarations;

  mkHomeConfiguration = import ./mkHomeConfiguration.nix {
    inherit inputs withSystem;
  };
  mkDarwinConfiguration = import ./mkDarwinConfiguration.nix {
    inherit inputs withSystem;
  };
in
{
  options = {
    # Authored declarations are internal inputs; `flake.blueprints` below is
    # the smaller public inventory used to select the resulting outputs.
    dotfiles.blueprintDeclarations = mkOption {
      type = types.attrsOf blueprintDeclarationType;
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
      _: blueprint: lib.nameValuePair blueprint.homeConfigurationName (mkHomeConfiguration blueprint)
    ) blueprintOutputSpecs;

    darwinConfigurations = lib.mapAttrs' (
      _: blueprint: lib.nameValuePair blueprint.darwinConfigurationName (mkDarwinConfiguration blueprint)
    ) blueprintOutputSpecs;

    blueprints = lib.mapAttrs (_: blueprint: {
      inherit (blueprint)
        darwinConfigurationName
        homeConfigurationName
        os
        system
        ;
      username = blueprint.user.name;
    }) blueprintOutputSpecs;
  };
}
