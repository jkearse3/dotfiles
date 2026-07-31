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
  inputs.darwin.lib.darwinSystem {
    inherit (blueprint) system;
    modules = [
      {
        nixpkgs.pkgs = unstablePkgs;

        system.primaryUser = blueprint.user.name;
        system.stateVersion = blueprint.darwin.stateVersion;
      }
      blueprint.darwin.module
    ];
  }
)
