{
  agentInteractivePolicy,
  agentLauncher,
  config,
  dotfilesPackages,
  dotfilesSource,
  pkgs,
  lib,
  mkNonoWrapper,
  mkSecretEnvironmentWrapper,
  mkSource,
  ...
}:
let
  renderAgentsMarkdown = import ../renderAgentsMarkdown.nix { inherit lib; };
  piRules = {
    delegation = ./rules/delegation.md;
  };

  renderPiSkillsDir = import ../renderSkillsDir.nix {
    inherit lib pkgs;
    skills = config.agents.skills;
  };

  # Herdr ships the authoritative Pi lifecycle and session integration beside
  # its binary. Editable delivery reaches it through the stable user-profile
  # link tracked in `extensions/herdr-agent-state.ts`; locked delivery replaces
  # that relative link with this exact package artifact.
  herdrPiIntegration = "${dotfilesPackages.herdr}/share/herdr/integrations/pi/herdr-agent-state.ts";
  herdrPiIntegrationChecked =
    pkgs.runCommandLocal "pi-herdr-integration-checked"
      {
        nativeBuildInputs = [
          pkgs.coreutils
          pkgs.gnugrep
        ];
      }
      ''
        expectedTarget='../../../../../../.nix-profile/share/herdr/integrations/pi/herdr-agent-state.ts'
        actualTarget="$(readlink ${./extensions}/herdr-agent-state.ts)"
        if [[ "$actualTarget" != "$expectedTarget" ]]; then
          echo "pi Herdr integration link target mismatch: $actualTarget" >&2
          exit 1
        fi

        test -s ${herdrPiIntegration}
        grep -Fxq '// HERDR_INTEGRATION_ID=pi' ${herdrPiIntegration}
        grep -Eq '^// HERDR_INTEGRATION_VERSION=[0-9]+$' ${herdrPiIntegration}
        ln -s ${herdrPiIntegration} $out
      '';

  # Locked mode cannot use the editable checkout's gitignored `node_modules`.
  # Build a complete immutable extension root from the same lockfile used by
  # editable npm installs. In normal mode mkSource points Pi directly at the
  # checkout, where npm owns runtime dependencies.
  piExtensionsLocked = pkgs.runCommandLocal "pi-extensions-locked" { } ''
    mkdir -p $out
    cp -R ${./extensions}/. $out/
    rm -rf $out/node_modules $out/.pi-types $out/herdr-agent-state.ts
    ln -s ${dotfilesPackages.pi-extension-deps}/node_modules $out/node_modules
    ln -s ${herdrPiIntegrationChecked} $out/herdr-agent-state.ts
  '';
  piExtensionsSource = if dotfilesSource.editable then mkSource ./extensions else piExtensionsLocked;

  nono-pi-entrypoint = mkNonoWrapper {
    name = "pi-entrypoint";
    profile = "coding-agents";
    command = lib.getExe dotfilesPackages.pi;
  };

  # Caffeinate stays outermost so its idle-sleep assertion covers the whole
  # session. Secret resolution stays inside it but outside nono so the sandbox
  # never needs access to the machine's provider. EXA_API_KEY is optional: when
  # absent, the interpolated header is empty and Exa continues on its
  # anonymous free tier.
  mkPi =
    {
      name,
      command,
    }:
    let
      secretEnvironment = mkSecretEnvironmentWrapper {
        name = "${name}-secret-environment";
        environmentName = "pi";
        inherit command;
      };
    in
    pkgs.writeShellApplication {
      inherit name;
      # Apply the non-interactive policy to the secret wrapper, nono, Pi, and
      # every command Pi runs without changing the user's interactive shell.
      text = ''
        ${agentInteractivePolicy.shellExports}
        ${agentLauncher { commandLine = ''${lib.getExe secretEnvironment} "$@"''; }}
      '';
    };

  pi = mkPi {
    name = "pi";
    command = lib.getExe dotfilesPackages.pi;
  };
  nono-pi = mkPi {
    name = "nono-pi";
    command = "${nono-pi-entrypoint}/bin/nono-pi-entrypoint";
  };
in
{
  imports = [
    ../../lib/source.nix
    ../../secrets
  ];

  config = {
    # Home Manager merges these keys into the writable settings file on every
    # switch, so a declared value replaces whatever Pi wrote. Pi keeps every
    # undeclared key, including `defaultProvider`, `defaultModel`, and the
    # `packages` entries `pi install` writes. Removing a key here leaves its
    # last value in the file until it is edited by hand.
    programs.pi-coding-agent = {
      enable = true;

      # `pi` and `nono-pi` below are the only Pi executables on PATH.
      package = null;

      mutableSettings = true;
      settings = {
        theme = "tokyonight";

        # Suppresses the changelog screen. Pi stamps this key only when it is
        # unset or the changelog holds newer entries, so a version above every
        # release is never rewritten.
        lastChangelogVersion = "999.999.999";

        # Without it pi runs `/bin/bash`, which is bash 3.2 on macOS.
        shellPath = config.agents.shellPath;
      };
    };

    home = {
      packages = [
        pi
        nono-pi
      ];

      extraBuilderCommands = ''
        mkdir -p $out/state
        ln -s ${herdrPiIntegrationChecked} $out/state/pi-herdr-integration-checked

        # The extensions themselves are delivered by symlink, so the generation
        # has no other reference to them and the check would never be built.
        ln -s ${dotfilesPackages.pi-extensions-checked} $out/state/pi-extensions-checked
      '';

      # Pi's `/mcp` command rewrites `enabled` and `exposure` values, so the
      # file must stay writable rather than a read-only Home Manager symlink.
      # Each switch merges the servers in `mcp.json` into it: declared fields
      # replace whatever Pi wrote, while undeclared servers and fields stay
      # Pi-owned. Removing a declaration leaves its last value in the file
      # until it is edited by hand. The Exa header keeps the literal
      # `${EXA_API_KEY}` reference, which Pi expands at runtime, so the key
      # never enters the Nix store.
      activation.piMcp = lib.hm.dag.entryAfter [ "linkGeneration" ] (
        lib.hm.generators.mkImpureConfigMerger {
          inherit pkgs;
          format = "json";
          empty = "{}";
          mode = "600";
          path = "${config.home.homeDirectory}/.pi/agent/mcp.json";
          staticSettings = ./mcp.json;
          jqOperation = "$dynamic * $static";
        }
      );

      file = {
        ".pi/agent/AGENTS.md".text = renderAgentsMarkdown {
          title = "Pi Instructions";
          registries = [
            {
              name = "shared";
              sources = config.agents.sharedRules;
            }
            {
              name = "pi";
              sources = piRules;
            }
          ];
          order = config.agents.sharedRuleOrder ++ [ "pi/delegation" ];
        };

        # Pi auto-discovers `<dir>/index.ts` under its standard global directory,
        # so a new extension needs no registration or Home Manager activation.
        # Editable mode points into the checkout; locked mode supplies an
        # immutable tree with the same lockfile-derived runtime dependencies.
        ".pi/agent/extensions".source = piExtensionsSource;
        ".pi/agent/skills" = renderPiSkillsDir { };
        ".pi/agent/themes/tokyonight.json".source = mkSource ./themes/tokyonight.json;
      };
    };
  };
}
