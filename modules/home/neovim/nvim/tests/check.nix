# Runs the Neovim configuration's plenary specs against the lockfile-pinned
# plugins that `tests/minimal_init.lua` loads. The plugins sit under the default
# `site` packpath because plenary's child Neovim processes reject an extended
# packpath.
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
}:
let
  neovimPluginLock = lib.importJSON ../nvim-pack-lock.json;

  # Fetches a plugin at the revision `nvim-pack-lock.json` pins, so the
  # tests exercise the plugins the Neovim configuration deploys.
  fetchLockedNeovimPlugin =
    pluginName:
    let
      lockedPlugin = neovimPluginLock.plugins.${pluginName};
      githubRepository = builtins.match "https://github.com/([^/]+)/([^/]+)" lockedPlugin.src;
    in
    assert lib.assertMsg (
      githubRepository != null
    ) "nvim-pack-lock.json: ${pluginName} source is not a GitHub repository: ${lockedPlugin.src}";
    builtins.fetchTree {
      type = "github";
      owner = builtins.elemAt githubRepository 0;
      repo = builtins.elemAt githubRepository 1;
      inherit (lockedPlugin) rev;
    };

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

    plugin_dir="$XDG_DATA_HOME/nvim/site/pack/locked/opt"
    mkdir -p "$plugin_dir"
    ln -s ${fetchLockedNeovimPlugin "plenary.nvim"} "$plugin_dir/plenary.nvim"
    ln -s ${fetchLockedNeovimPlugin "fzf-lua"} "$plugin_dir/fzf-lua"

    cp -R ${neovimTestSource} "$TMPDIR/nvim"
    chmod -R u+w "$TMPDIR/nvim"
    cd "$TMPDIR/nvim"

    nvim --headless -u tests/minimal_init.lua -i NONE \
      -c "lua require('plenary.test_harness').test_directory('tests', { sequential = true, minimal_init = 'tests/minimal_init.lua' })"

    touch "$out"
  ''
