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

  mkAgentLaunchers = import ../mkAgentLaunchers.nix {
    inherit
      agentInteractivePolicy
      agentLauncher
      lib
      mkNonoWrapper
      mkSecretEnvironmentWrapper
      pkgs
      ;
  };

  piExtensionsSource =
    if dotfilesSource.editable then mkSource ./extensions else dotfilesPackages.pi-extensions-locked;

  # The `pi` secret environment supplies EXA_API_KEY. It is optional: when
  # absent, the interpolated header is empty and Exa continues on its anonymous
  # free tier.
  piLaunchers = mkAgentLaunchers {
    name = "pi";
    command = lib.getExe dotfilesPackages.pi;
    secretEnvironment = "pi";
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
        piLaunchers.launcher
        piLaunchers.nonoLauncher
      ];

      extraBuilderCommands = ''
        # The extensions themselves are delivered by symlink, so the generation
        # has no other reference to them and the check, which also gates the
        # Herdr integration they link to, would never be built.
        mkdir -p $out/state
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
