{
  agentInteractivePolicy,
  agentLauncher,
  config,
  dotfilesPackages,
  pkgs,
  lib,
  mkNonoWrapper,
  mkSecretEnvironmentWrapper,
  ...
}:
let
  renderAgentsMarkdown = import ../renderAgentsMarkdown.nix { inherit lib; };
  piRules = {
    delegation = ./rules/delegation.md;
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
    ../../secrets
    ../rules.nix
    ../skills.nix
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
        # so a new extension needs no registration. The directory is an
        # immutable store tree with lockfile-derived runtime dependencies,
        # built only after the extensions type-check, so extension changes
        # reach Pi at the next switch.
        ".pi/agent/extensions".source = dotfilesPackages.pi-extensions-locked;
        ".pi/agent/skills" = {
          source = config.agents.skillsDir;
          recursive = true;
        };
        ".pi/agent/themes/tokyonight.json".source = ./themes/tokyonight.json;
      };
    };
  };
}
