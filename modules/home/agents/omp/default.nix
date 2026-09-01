{
  agentInteractivePolicy,
  config,
  dotfilesPackages,
  lib,
  mkNonoWrapper,
  mkSecretEnvironmentWrapper,
  pkgs,
  ...
}:
let
  renderAgentsMarkdown = import ../renderAgentsMarkdown.nix { inherit lib; };
  preventIdleSleep = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin "/usr/bin/caffeinate -i ";
  yaml = pkgs.formats.yaml { };

  # These are fallback defaults only. OMP owns the writable live file and its
  # settings UI or CLI wins whenever it has persisted a value.
  ompSeedSettings = {
    defaultThinkingLevel = "medium";
    modelRoles.default = "openai-codex/gpt-5.6-sol";
    providers.webSearchOrder = [ "exa" ];
    startup.checkUpdate = false;
    startup.quiet = true;
  };
  ompSettingsSeed = yaml.generate "omp-settings-seed.yml" ompSeedSettings;
  pythonWithXxhash = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.xxhash ]);

  ompSettingsMerge = pkgs.writeShellApplication {
    name = "omp-settings-merge";
    runtimeInputs = [
      pkgs.yq
      pythonWithXxhash
    ];
    text = ''
      exec python3 ${./omp-settings-merge.py} "$@"
    '';
  };
  ompSettingsMergeChecked =
    pkgs.runCommandLocal "omp-settings-merge-checked"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.yq
          pythonWithXxhash
        ];
      }
      ''
        bash ${./omp-settings-merge-test.sh} ${lib.getExe ompSettingsMerge}
        ln -s ${ompSettingsMerge} $out
      '';

  # Keep interactive VCS operations unavailable to OMP and every command it
  # launches, matching the other coding-agent entrypoints.
  omp-wrapped = pkgs.writeShellApplication {
    name = "omp";
    text = ''
      ${agentInteractivePolicy.shellExports}
      exec ${lib.getExe dotfilesPackages.omp} "$@"
    '';
  };

  nono-omp-entrypoint = mkNonoWrapper {
    name = "omp-entrypoint";
    profile = "coding-agents";
    command = "${omp-wrapped}/bin/omp";
  };

  # Secret resolution remains outside nono so a sandbox never needs access to
  # the machine-local provider. EXA_API_KEY is optional for OMP's web search.
  mkOmp =
    {
      name,
      command,
    }:
    let
      secretEnvironment = mkSecretEnvironmentWrapper {
        name = "${name}-secret-environment";
        environmentName = "omp";
        inherit command;
        allowMissingProvider = true;
      };
    in
    pkgs.writeShellApplication {
      inherit name;
      text = ''
        exec ${preventIdleSleep}${lib.getExe secretEnvironment} "$@"
      '';
    };

  omp = mkOmp {
    name = "omp";
    command = "${omp-wrapped}/bin/omp";
  };
  nono-omp = mkOmp {
    name = "nono-omp";
    command = "${nono-omp-entrypoint}/bin/nono-omp-entrypoint";
  };

  # Generate completion from the pinned binary and validate the settings keys
  # against that same release. Dynamic completion bypasses secret resolution.
  ompFishCompletionChecked =
    pkgs.runCommandLocal "omp-fish-completion-checked"
      {
        nativeBuildInputs = [
          dotfilesPackages.omp
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.jq
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME/.omp/agent"
        install -m 600 ${ompSettingsSeed} "$HOME/.omp/agent/config.yml"

        test "$(omp config get modelRoles --json | jq -r .value.default)" = ${lib.escapeShellArg ompSeedSettings.modelRoles.default}
        test "$(omp config get defaultThinkingLevel --json | jq -r .value)" = ${lib.escapeShellArg ompSeedSettings.defaultThinkingLevel}
        test "$(omp config get providers.webSearchOrder --json | jq -c .value)" = '["exa"]'
        test "$(omp config get startup.checkUpdate --json | jq -r .value)" = false
        test "$(omp config get startup.quiet --json | jq -r .value)" = true

        omp completions fish > "$out"
        grep -qF "complete -c omp" "$out"
        substituteInPlace "$out" \
          --replace-fail "command omp __complete" "${omp-wrapped}/bin/omp __complete"
        ! grep -qF "command omp __complete" "$out"
      '';
in
{
  imports = [
    ../../nono
    ../../secrets
    ../registries.nix
  ];

  config = {
    home = {
      packages = [
        omp
        nono-omp
      ];

      activation.ompSettings =
        lib.hm.dag.entryAfter [ "writeBoundary" ] # bash
          ''
            run ${ompSettingsMergeChecked}/bin/omp-settings-merge \
              "$HOME/.omp/agent" \
              ${ompSettingsSeed}
          '';

      file = {
        ".omp/agent/AGENTS.md".text = renderAgentsMarkdown {
          title = "OMP Instructions";
          registries = [
            {
              name = "shared";
              sources = config.agents.sharedRules;
            }
          ];
          order = config.agents.sharedRuleOrder;
        };
        ".config/fish/completions/omp.fish".source = ompFishCompletionChecked;
        ".config/fish/completions/nono-omp.fish".text = ''
          complete -c nono-omp --wraps omp
        '';
      };
    };
  };
}
