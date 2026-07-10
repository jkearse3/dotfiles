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
  home = {
    packages = [
      pkgs.copilot-language-server
      pkgs.neovim
      pkgs.tree-sitter
    ];
    sessionVariables = {
      EDITOR = "nvim";
    };
    file.".config/nvim".source = mkSource ./nvim;
  };
}
