{
  config,
  dotfilesPackages,
  lib,
  mkSource,
  pkgs,
  ...
}:
let
  # Keep Neovim socket paths below macOS's limit when direnv lengthens TMPDIR.
  darwinRuntimeDirectoryWrapperArgs = lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
    "--run"
    ''
      if [ -z "''${XDG_RUNTIME_DIR:-}" ]; then
        darwin_runtime_directory="$(/usr/bin/getconf DARWIN_USER_TEMP_DIR || true)"
        if [ -n "$darwin_runtime_directory" ]; then
          export XDG_RUNTIME_DIR="''${darwin_runtime_directory%/}"
        fi
      fi
    ''
  ];
in
{
  imports = [ ../lib/source.nix ];

  programs.neovim = {
    enable = true;
    extraWrapperArgs = darwinRuntimeDirectoryWrapperArgs;
    # Optional plugins land in the pack's `opt` directory, so nothing loads
    # until lib.config.run calls `:packadd` with each spec's plugin names.
    plugins = map (plugin: {
      inherit plugin;
      optional = true;
    }) (builtins.attrValues (import ./plugins.nix pkgs.vimPlugins));
    sideloadInitLua = true;
    withNodeJs = false;
    withPerl = false;
    withPython3 = false;
    withRuby = false;
  };

  home = {
    packages = [ dotfilesPackages.nvim-pack ];
    sessionVariables = {
      EDITOR = "nvim";
    };
    file.".config/nvim".source = mkSource ./nvim;

    # Earlier setups installed plugins with vim.pack into site/pack/core and
    # compiled tree-sitter parsers and queries into site/parser, parser-info,
    # and queries. Left in place, the clones would load beside the Nix copies
    # in site/pack/hm, and site/parser and site/queries precede site/pack/hm on
    # 'runtimepath', so stale parsers and queries would win. This removes them
    # on every switch; site/pack/hm belongs to Home Manager. Delete this step
    # and ./migrate-neovim-site once every machine has switched past it, so no
    # machine still has those leftovers.
    activation.migrateNeovimSiteLeftovers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe (pkgs.callPackage ./migrate-neovim-site/package.nix { })} \
        ${lib.escapeShellArg "${config.xdg.dataHome}/nvim/site"}
    '';
  };
}
