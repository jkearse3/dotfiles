{ pkgs, ... }:

{
  home.packages = [ (pkgs.callPackage ./package.nix { }) ];
  agents.extraSkills."playwright-cli" = ./skill;
}
