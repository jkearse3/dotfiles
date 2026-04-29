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
  home.packages = [
    pkgs.copilot-language-server
    pkgs.neovim
    pkgs.tree-sitter
  ];
  home.sessionVariables = {
    EDITOR = "nvim";
  };
  home.file.".config/nvim".source = mkSource ./nvim;
}
