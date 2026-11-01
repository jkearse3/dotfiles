# Registers the standalone tests and lint checks that `nix flake check` runs,
# and the `lint` package that builds only the lint checks.
#
# A test runs in the derivation that delivers what it tests, or, when nothing
# builds it, as a check registered explicitly here. Repository packages run
# their tests at build time, but the home build does not necessarily build
# every package, so they are registered here too.
#
# A check that only runs a script with some tools is defined here with
# `mkScriptCheck`, and a linter run over repository files with `mkLintCheck`. A
# check that needs more lives in its own `check.nix` next to its tests and is
# registered here with `callPackage`, as `flake/packages.nix` registers
# `packages/*/package.nix`.
{
  perSystem =
    {
      config,
      lib,
      pkgs,
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

      # Builds a check that runs `command`, a linter invocation, from the root
      # of a read-only copy of `fileset`, a subset of the repository, with
      # `tools` on PATH. The check fails when `command` fails. Only files in
      # the flake source are linted, so untracked files are not. HOME and the
      # XDG cache point into the build's temporary directory, so linters
      # cannot read user configuration.
      mkLintCheck =
        {
          name,
          fileset,
          tools,
          command,
        }:
        let
          src = lib.fileset.toSource {
            root = ../.;
            inherit fileset;
          };
        in
        unstablePkgs.runCommand name
          {
            nativeBuildInputs = tools;
          }
          ''
            export HOME="$TMPDIR/home"
            export XDG_CACHE_HOME="$TMPDIR/xdg/cache"
            mkdir -p "$HOME" "$XDG_CACHE_HOME"

            cd ${src}
            ${command}

            touch "$out"
          '';

      # The linters, run over the files in the flake source. `packages.lint`
      # builds them together, and they are flake checks individually.
      lintChecks = {
        lint-nix = mkLintCheck {
          name = "lint-nix";
          fileset = lib.fileset.fileFilter (file: file.hasExt "nix") ../.;
          tools = [
            unstablePkgs.statix
            unstablePkgs.deadnix
          ];
          command = ''
            echo "Linting Nix files..."
            statix check .
            deadnix --fail .
          '';
        };

        # `.shellcheckrc` enables `external-sources`, so the fileset also
        # carries every file a script sources, provided scripts source only other
        # `.sh` or `.bash` files.
        lint-shell = mkLintCheck {
          name = "lint-shell";
          fileset = lib.fileset.unions [
            ../.shellcheckrc
            (lib.fileset.fileFilter (file: file.hasExt "sh" || file.hasExt "bash") ../.)
          ];
          tools = [
            unstablePkgs.findutils
            unstablePkgs.shellcheck
          ];
          command = ''
            echo "Linting shell scripts..."
            find . -type f \( -name '*.sh' -o -name '*.bash' \) -print0 | sort -z | xargs -0 shellcheck
          '';
        };

        # `pyrefly.toml` selects the checked directories and import roots, so
        # the fileset carries every Python source and project file rather than
        # repeating that list.
        lint-python = mkLintCheck {
          name = "lint-python";
          fileset = lib.fileset.unions [
            ../pyrefly.toml
            (lib.fileset.fileFilter (
              file: file.hasExt "py" || file.hasExt "pyi" || file.name == "pyproject.toml"
            ) ../.)
          ];
          # Pyrefly queries the interpreter for the Python version and
          # platform; without one it falls back to defaults that report
          # different diagnostics than an editor or shell with Python does.
          tools = [
            unstablePkgs.pyrefly
            unstablePkgs.python3
          ];
          command = ''
            echo "Checking Python types..."
            pyrefly check --min-severity warn
          '';
        };
      };
    in
    {
      # Builds every lint check and the pi extension checks, so
      # `nix build .#lint` runs all lint without the slower tests.
      packages.lint = unstablePkgs.linkFarm "lint" (
        lintChecks // { inherit (config.packages) pi-extensions-checked; }
      );

      # treefmt-nix contributes the `treefmt` check; the module system merges it
      # with these.
      checks =
        config.packages
        // lintChecks
        // {
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

          # Runs the `nix` wrapper that snapshots jj against stub jj and Nix,
          # built with the same nixpkgs as the wrapper the home profile installs.
          nix-jj-snapshot-behavior = pkgs.callPackage ../packages/nix-jj-snapshot/check.nix { };

          manifest-policy = unstablePkgs.callPackage ../modules/home/secrets/tests/check.nix { };
          secret-wrappers = unstablePkgs.callPackage ../modules/home/secrets/tests/check.nix {
            test = "secret-wrappers";
          };

          # Runs the Neovim configuration's plenary specs on the lockfile-pinned
          # plugins.
          neovim = unstablePkgs.callPackage ../modules/home/neovim/nvim/tests/check.nix {
            inherit (config.packages) jjx;
          };

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
