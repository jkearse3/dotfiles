# The Neovim plugins this configuration loads, keyed by the name `:packadd`
# and the Lua specs in `nvim/lua/config` use for each (the derivation's
# `pname`). This is the single plugin list: the Home Manager module installs
# these derivations, and the `neovim` flake check takes its test plugins from
# here, so both use the same nixpkgs revisions.
vimPlugins: {
  "blink.cmp" = vimPlugins.blink-cmp;
  "conform.nvim" = vimPlugins.conform-nvim;
  "fzf-lua" = vimPlugins.fzf-lua;
  "gitsigns.nvim" = vimPlugins.gitsigns-nvim;
  "nvim-dap" = vimPlugins.nvim-dap;
  "nvim-dap-go" = vimPlugins.nvim-dap-go;
  "nvim-lint" = vimPlugins.nvim-lint;
  # Every grammar and its queries, so no language needs a runtime parser build.
  "nvim-treesitter" = vimPlugins.nvim-treesitter.withAllGrammars;
  "oil.nvim" = vimPlugins.oil-nvim;
  "plenary.nvim" = vimPlugins.plenary-nvim;
  "tokyonight.nvim" = vimPlugins.tokyonight-nvim;
  "vim-test" = vimPlugins.vim-test;
}
