# Registers the standalone tests that `nix flake check` and `./x.sh check` run.
#
# A test runs in the derivation that delivers what it tests, or, when nothing
# builds it, as a check registered explicitly here. Repository packages run
# their tests at build time, but the home build does not necessarily build
# every package, so they are registered here too.
#
# A check that only runs a script with some tools is defined here with
# `mkScriptCheck`. A check that needs more lives in its own `check.nix` next to
# its tests and is registered here with `callPackage`, as `flake/packages.nix`
# registers `packages/*/package.nix`.
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

        manifest-policy = unstablePkgs.callPackage ../modules/home/secrets/tests/check.nix { };
        secret-wrappers = unstablePkgs.callPackage ../modules/home/secrets/tests/check.nix {
          test = "secret-wrappers";
        };

        # Runs the Neovim configuration's plenary specs on the lockfile-pinned
        # plugins.
        neovim = unstablePkgs.callPackage ../modules/home/neovim/nvim/tests/check.nix {
          inherit (config.packages) jjx;
        };

        # Runs `interactive-policy-test.sh` against the agent jj and git shims.
        # The home build also links this check, but `./x.sh check` does not
        # build the home configuration. Uses the same arguments the home
        # module passes, so both build the same derivation.
        agent-interactive-policy =
          (import ../modules/home/agents/interactive-policy.nix {
            inherit lib;
            pkgs = unstablePkgs;
            agentInteractiveDenied = config.packages.agent-interactive-denied;
          }).check;

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
