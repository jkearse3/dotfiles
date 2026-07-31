{
  mkSource,
  pkgs,
  ...
}:
{
  imports = [ ../lib/source.nix ];

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
