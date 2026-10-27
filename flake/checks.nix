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
      # script exits non-zero.
      mkScriptCheck =
        {
          name,
          src,
          script,
          tools,
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

            bash "$TMPDIR/src/${script}"

            touch "$out"
          '';
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
      };
    };
}
