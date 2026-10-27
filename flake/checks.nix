# Registers the standalone tests that `nix flake check` and `./x.sh check` run.
#
# A test runs in the derivation that delivers what it tests, or, when nothing
# builds it, as a check registered explicitly here. Repository packages run
# their tests at build time, but the home build does not necessarily build
# every package, so they are registered here too.
{
  perSystem =
    {
      config,
      lib,
      unstablePkgs,
      ...
    }:
    let
      # Builds a check that runs `script`, a Bash test relative to `src`, in a
      # writable copy of `src` with `tools` on PATH. HOME and the XDG base
      # directories point into the build's temporary directory, so the test
      # cannot read or write user configuration. The check fails when the
      # script exits non-zero or when its standard output lacks any of
      # `requiredOutputLines` as an exact line, which catches a test that
      # silently skips cases whose prerequisites are missing.
      mkScriptCheck =
        {
          name,
          src,
          script,
          tools,
          requiredOutputLines ? [ ],
        }:
        unstablePkgs.runCommand name
          {
            nativeBuildInputs = tools;
          }
          ''
            cp -R ${src} "$TMPDIR/src"
            chmod -R u+w "$TMPDIR/src"
            patchShebangs "$TMPDIR/src"

            export HOME="$TMPDIR/home"
            export XDG_CONFIG_HOME="$TMPDIR/xdg/config"
            export XDG_DATA_HOME="$TMPDIR/xdg/data"
            export XDG_STATE_HOME="$TMPDIR/xdg/state"
            export XDG_CACHE_HOME="$TMPDIR/xdg/cache"
            mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

            set -o pipefail
            bash "$TMPDIR/src/${script}" | tee "$TMPDIR/script-output.log"
            ${lib.concatMapStrings (line: ''
              grep -qxF -- ${lib.escapeShellArg line} "$TMPDIR/script-output.log" \
                || { echo ${lib.escapeShellArg "missing required output line: ${line}"} >&2; exit 1; }
            '') requiredOutputLines}

            touch "$out"
          '';

      neovimConfig = ../modules/home/neovim/nvim;
      neovimPluginLock = lib.importJSON (neovimConfig + "/nvim-pack-lock.json");

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
    in
    {
      # treefmt-nix contributes the `treefmt` check; the module system merges it
      # with these.
      checks = config.packages // {
        x-ssh-agent = mkScriptCheck {
          name = "x-ssh-agent";
          src = lib.fileset.toSource {
            root = ../.;
            fileset = lib.fileset.unions [
              ../x.sh
              ../tests/x-ssh-agent.sh
            ];
          };
          script = "tests/x-ssh-agent.sh";
          tools = [
            unstablePkgs.python3
            unstablePkgs.openssh
          ];
        };

        implement-skill-scripts = mkScriptCheck {
          name = "implement-skill-scripts";
          src = lib.fileset.toSource {
            root = ../modules/home/agents/skills/implement;
            fileset = lib.fileset.unions [
              ../modules/home/agents/skills/implement/scripts
              ../modules/home/agents/skills/implement/tests
            ];
          };
          script = "tests/implement-scripts.sh";
          tools = [
            unstablePkgs.git
            unstablePkgs.jujutsu
            unstablePkgs.coreutils
          ];
        };

        # Runs the Neovim configuration's plenary specs against the
        # lockfile-pinned plugins that `tests/minimal_init.lua` loads. The
        # plugins sit under the default `site` packpath because plenary's child
        # Neovim processes reject an extended packpath.
        neovim =
          let
            neovimTestSource = lib.fileset.toSource {
              root = neovimConfig;
              fileset = lib.fileset.unions [
                (neovimConfig + "/lua")
                (neovimConfig + "/tests")
              ];
            };
          in
          unstablePkgs.runCommand "neovim"
            {
              nativeBuildInputs = [
                unstablePkgs.neovim-unwrapped
                unstablePkgs.git
                unstablePkgs.jujutsu
                unstablePkgs.fzf
                unstablePkgs.jq
                config.packages.jjx
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
            '';

        handoff-skill-scripts = mkScriptCheck {
          name = "handoff-skill-scripts";
          src = lib.fileset.toSource {
            root = ../modules/home/agents/skills/handoff;
            fileset = lib.fileset.unions [
              ../modules/home/agents/skills/handoff/scripts
              ../modules/home/agents/skills/handoff/tests
            ];
          };
          script = "tests/handoff-scripts.sh";
          tools = [
            unstablePkgs.git
            unstablePkgs.jujutsu
            unstablePkgs.coreutils
            config.packages.jjx
          ];
          # The test skips its jj cases when jj or jjx is missing from PATH.
          requiredOutputLines = [ "ok - non-Git jj workspace resolves its default workspace" ];
        };
      };
    };
}
