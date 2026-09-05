{
  agentInteractivePolicy,
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
  cfg = config.agents.pi;
  preventIdleSleep = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin "/usr/bin/caffeinate -i ";

  renderAgentsMarkdown = import ../renderAgentsMarkdown.nix { inherit lib; };

  renderPiSkillsDir = import ../renderSkillsDir.nix {
    inherit lib pkgs;
    skills = config.agents.skills;
  };

  # Fallback defaults for keys pi rewrites as the user changes theme, provider,
  # model, thinking level, or TUI mode in the app. The merge lets the live value
  # win, so these only fill keys pi has not written.
  #
  # `lastChangelogVersion` suppresses the changelog screen. Pi stamps that key
  # only when it is unset or the changelog holds newer entries, so a version
  # above every release is written once and never rewritten.
  seedSettings = {
    theme = "tokyonight";
    defaultProvider = "openai-codex";
    defaultModel = "gpt-5.6-sol";
    defaultThinkingLevel = "medium";
    tuiMode = "fullscreen";
    lastChangelogVersion = "999.999.999";
  };

  seedFile = pkgs.writeText "pi-settings-seed.json" (builtins.toJSON seedSettings);

  # Recorded into the generation rather than into ~/.pi, following
  # `modules/misc/dconf.nix`, so the set Nix owns rolls back with the generation
  # and needs no state file of its own.
  packagesFile = pkgs.writeText "pi-packages.json" (builtins.toJSON cfg.packages);
  packagesStatePath = "state/pi-packages.json";

  piSettingsMerge = pkgs.writeShellApplication {
    name = "pi-settings-merge";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = builtins.readFile ./pi-settings-merge.sh;
  };

  # A merge regression drops settings pi wrote without saying so, and activation
  # is a bad place to discover that. Gate the script on its fixtures at build
  # time instead, and hand the module only the checked path.
  piSettingsMergeChecked =
    pkgs.runCommandLocal "pi-settings-merge-checked"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.jq
        ];
      }
      ''
        bash ${./pi-settings-merge-test.sh} ${piSettingsMerge}/bin/pi-settings-merge
        ln -s ${piSettingsMerge} $out
      '';

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

  # A repository-authored extension is a directory holding an `index.ts`, so
  # this is empty whenever none are declared. Herdr's release-owned root file is
  # checked separately above; this flag gates checks requiring local fixtures.
  piExtensionNames = lib.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./extensions)
  );
  hasPiExtensions = piExtensionNames != [ ];

  # Editable delivery points `~/.pi/agent/extensions` at the checkout, so nothing
  # forces a rebuild when a working-tree edit lands and no derivation ever sees
  # that edit. This gates the committed sources instead: a rejected import, a
  # type error, or a failing fixture fails the build and therefore the switch.
  # `./x.sh lint-typescript` runs the same three checks against the working tree
  # between commits.
  piExtensionsChecked =
    pkgs.runCommandLocal "pi-extensions-checked"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.findutils
          pkgs.nodejs
          pkgs.typescript
        ];
      }
      ''
        # The import checker reads specifiers with the TypeScript preprocessor.
        export NODE_PATH=${pkgs.typescript}/lib/node_modules

        bash ${./extension-imports-check-test.sh} ${./extension-imports-check.mjs}
        node ${./extension-imports-check.mjs} ${./extensions}

        # Runtime dependencies and Pi's declaration-only module tree have
        # separate owners. Keeping them separate prevents npm from replacing Pi
        # types and prevents declarations from masquerading as runtime packages.
        cp -R ${./extensions} ./extensions
        chmod -R u+w ./extensions
        rm -rf ./extensions/node_modules ./extensions/.pi-types
        ln -s ${dotfilesPackages.pi-extension-deps}/node_modules ./extensions/node_modules
        ln -s ${dotfilesPackages.pi-extension-types}/node_modules ./extensions/.pi-types

        tsc -p ./extensions

        # Node strips types natively, so the fixtures run straight from source
        # with no build step and no resolver: `events.ts` imports pi for types
        # only. An empty match would make this step silently vacuous.
        readarray -t -d "" extensionTests < <(
          find ./extensions -name '*.test.ts' -type f -print0 | sort -z
        )
        if [[ ''${#extensionTests[@]} -eq 0 ]]; then
          echo "pi-extensions-checked: no extension fixtures found" >&2
          exit 1
        fi
        node --test "''${extensionTests[@]}"

        touch $out
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

  # Scope the non-interactive policy to Pi and every command it shells out to
  # without changing the user's interactive shell.
  pi-wrapped = pkgs.writeShellApplication {
    name = "pi";
    text = ''
      ${agentInteractivePolicy.shellExports}
      exec ${dotfilesPackages.pi}/bin/pi "$@"
    '';
  };

  nono-pi-entrypoint = mkNonoWrapper {
    name = "pi-entrypoint";
    profile = "coding-agents";
    command = "${pi-wrapped}/bin/pi";
  };

  # Gate the secret wrapper on the concrete sandbox entrypoint without running
  # nono or resolving machine-local secrets during the build.
  nono-pi-entrypoint-checked = pkgs.runCommandLocal "nono-pi-entrypoint-checked" { } ''
    test -x ${nono-pi-entrypoint}/bin/nono-pi-entrypoint
    ln -s ${nono-pi-entrypoint} $out
  '';

  # Caffeinate stays outermost so its idle-sleep assertion covers the whole
  # session. Secret resolution stays inside it but outside nono so the sandbox
  # never needs access to the machine's provider. EXA_API_KEY is optional: when
  # absent, the adapter's interpolated header is empty and Exa continues on its
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
        allowMissingProvider = true;
      };
    in
    pkgs.writeShellApplication {
      inherit name;
      text = ''
        exec ${preventIdleSleep}${lib.getExe secretEnvironment} "$@"
      '';
    };

  pi = mkPi {
    name = "pi";
    command = "${pi-wrapped}/bin/pi";
  };
  nono-pi = mkPi {
    name = "nono-pi";
    command = "${nono-pi-entrypoint-checked}/bin/nono-pi-entrypoint";
  };
in
{
  imports = [
    ../../lib/source.nix
    ../../secrets
  ];

  options.agents.pi.packages = lib.mkOption {
    type = lib.types.listOf (lib.types.either lib.types.str (lib.types.attrsOf lib.types.anything));
    default = [ ];
    example = [
      "npm:@example/pi-pack"
      {
        source = "https://github.com/example/pi-pack";
        skills = [ "review" ];
      }
    ];
    description = ''
      Third-party pi packages to install, as `npm:`/`git:`/absolute-path
      sources. The attribute set form carries the `pi config` resource filters
      alongside a `source` key.

      Nix owns these entries additively: changing or removing one here reaches
      `~/.pi/agent/settings.json` on the next activation, but entries installed
      with `pi install` are never touched. Pi replaces arrays wholesale when it
      merges settings, so this list must not be written into the live file
      directly.

      Pin every entry to an exact version (`npm:@scope/pack@1.2.3`, `git:...@tag`).
      Pi installs a missing package when it starts, so an unpinned source
      resolves to whatever is newest at that moment, on a schedule nobody chose,
      and a generation rollback restores this entry without restoring the tree
      that was installed for it.

      Entries are matched the way pi matches them — an npm source by bare
      package name, a git source by host and path, a local source by resolved
      path — so re-installing a declared package at another version updates the
      existing entry in place, and pi's value for it stands until this list
      changes.
    '';
  };

  config = {
    agents.pi.packages = [
      # Pi has no MCP support of its own; this adds it. The shared agent module
      # delivers Exa through `~/.agents/mcp.json`, which the adapter treats as a
      # read-only input while keeping pi-specific overrides writable under
      # `~/.pi/agent/mcp.json` and project `.pi/mcp.json` files.
      "npm:pi-mcp-adapter@2.27.0"
    ];

    home = {
      packages = [
        pi
        nono-pi
      ];

      extraBuilderCommands = ''
        mkdir -p $out/state
        ln -s ${packagesFile} $out/${packagesStatePath}
        ln -s ${herdrPiIntegrationChecked} $out/state/pi-herdr-integration-checked

        ${lib.optionalString hasPiExtensions ''
          # The extensions themselves are delivered by symlink, so the generation
          # has no other reference to them and the check would never be built.
          ln -s ${piExtensionsChecked} $out/state/pi-extensions-checked
        ''}
      '';

      activation.piSettings =
        lib.hm.dag.entryAfter [ "writeBoundary" ] # bash
          ''
            # Unset on a first activation, and pointing at a generation without
            # the state file on the first switch after this option existed. The
            # merge treats either as an empty Nix-owned set.
            piPreviousPackages=""
            if [[ -v oldGenPath ]]; then
              piPreviousPackages="$oldGenPath/${packagesStatePath}"
            fi

            run ${piSettingsMergeChecked}/bin/pi-settings-merge \
              "$HOME/.pi/agent/settings.json" \
              ${seedFile} \
              ${packagesFile} \
              "$piPreviousPackages"
            unset piPreviousPackages
          '';

      file = {
        ".pi/agent/AGENTS.md".text = renderAgentsMarkdown {
          title = "Pi Instructions";
          registries = [
            {
              name = "shared";
              sources = config.agents.sharedRules;
            }
          ];
          order = config.agents.sharedRuleOrder;
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
