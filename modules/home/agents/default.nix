{
  config,
  pkgs,
  lib,
  self,
  repoRoot,
  editable,
  ...
}:
let
  mkSource = import ../mkSource.nix {
    inherit
      config
      self
      lib
      repoRoot
      editable
      ;
  };
in
{
  imports = [
    ./claude
    ./opencode
  ];
  home.file = {
    ".agents/rules".source = mkSource ./rules;
    ".agents/skills".source = mkSource ./skills;
  };
}
