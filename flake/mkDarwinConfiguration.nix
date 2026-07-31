{
  inputs,
  withSystem,
}:
blueprint:
withSystem blueprint.system (
  {
    unstablePkgs,
    ...
  }:
  let
    darwinBaselineModule = {
      nixpkgs.pkgs = unstablePkgs;

      system.primaryUser = blueprint.user.name;
      system.stateVersion = blueprint.darwin.stateVersion;
    };
  in
  inputs.darwin.lib.darwinSystem {
    inherit (blueprint) system;
    modules = [
      darwinBaselineModule
      blueprint.darwin.module
    ];
  }
)
