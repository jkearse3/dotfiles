# Runs the Neovim configuration's plenary specs against the plenary.nvim and
# fzf-lua derivations from `modules/home/neovim/plugins.nix`, the same ones Home
# Manager installs, which `tests/minimal_init.lua` loads. The plugins sit under
# the default `site` packpath because plenary's child Neovim processes reject an
# extended packpath.
#
# `flake/checks.nix` registers this as the `neovim` check with `callPackage`.
{
  fzf,
  git,
  jjx,
  jq,
  jujutsu,
  lib,
  neovim-unwrapped,
  runCommand,
  vimPlugins,
}:
let
  neovimPlugins = import ../../plugins.nix vimPlugins;

  # Excludes this runner, so editing it does not change the tested source.
  neovimTestSource = lib.fileset.toSource {
    root = ./..;
    fileset = lib.fileset.difference (lib.fileset.unions [
      ../lua
      ./.
    ]) ./check.nix;
  };
in
runCommand "neovim"
  {
    nativeBuildInputs = [
      neovim-unwrapped
      git
      jujutsu
      fzf
      jq
      jjx
    ];
  }
  ''
    export HOME="$TMPDIR/home"
    export XDG_CONFIG_HOME="$TMPDIR/xdg/config"
    export XDG_DATA_HOME="$TMPDIR/xdg/data"
    export XDG_STATE_HOME="$TMPDIR/xdg/state"
    export XDG_CACHE_HOME="$TMPDIR/xdg/cache"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

    plugin_dir="$XDG_DATA_HOME/nvim/site/pack/test/opt"
    mkdir -p "$plugin_dir"
    ln -s ${neovimPlugins."plenary.nvim"} "$plugin_dir/plenary.nvim"
    ln -s ${neovimPlugins."fzf-lua"} "$plugin_dir/fzf-lua"

    cp -R ${neovimTestSource} "$TMPDIR/nvim"
    chmod -R u+w "$TMPDIR/nvim"
    cd "$TMPDIR/nvim"

    nvim --headless -u tests/minimal_init.lua -i NONE \
      -c "lua require('plenary.test_harness').test_directory('tests', { sequential = true, minimal_init = 'tests/minimal_init.lua' })"

    touch "$out"
  ''
