{
  dotfilesPackages,
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
      dotfilesPackages.nvim-pack-prune
    ];
    sessionVariables = {
      EDITOR = "nvim";
    };
    file.".config/nvim".source = mkSource ./nvim;
  };
}
