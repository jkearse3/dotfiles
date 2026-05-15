{
  config,
  dotfilesPackages,
  pkgs,
  lib,
  mkNonoWrapper,
  mkSource,
  ...
}:
let
  cfg = config.agents.pi;

  renderAgentsMarkdown = import ../renderAgentsMarkdown.nix { inherit lib; };

  # Pi-only skills sit beside the shared registry rather than in it:
  # `exa-web-search` targets the Exa MCP server delivered for pi, while claude
  # has its own web search and opencode reaches Exa through its own integration.
  #
  # The shared registry has to come too. `.pi/agent/AGENTS.md` below is stitched
  # from `agents.sharedRules`, which route revision shaping through the
  # finalize-changes skill; without the registry pi is instructed to use skills
  # it cannot see. Claude and opencode both compose `config.agents.skills` the
  # same way.
  piLocalSkills = lib.mapAttrs (name: _: ./skills/${name}) (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./skills)
  );
  duplicatePiSkillNames = lib.intersectLists (lib.attrNames piLocalSkills) (
    lib.attrNames config.agents.skills
  );
  renderPiSkillsDir = import ../renderSkillsDir.nix {
    inherit lib pkgs;
    skills = config.agents.skills // piLocalSkills;
  };

  # Fallback defaults for keys pi rewrites as the user changes theme, provider,
  # model, thinking level, or TUI mode in the app. The merge lets the live value
  # win, so these only fill keys pi has not written.
  #
  # `lastChangelogVersion` suppresses the changelog screen. Pi stamps that key
  # only when it is unset or the changelog holds newer entries, so a version
  # above every release is written once and never rewritten.
  seedSettings = {
    theme = "dark";
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

  # An extension is a directory holding an `index.ts`, so this is empty whenever
  # none are declared. Pi discovers whatever is delivered, and a tree carrying
  # only build scaffolding is worth neither delivering nor checking, so both the
  # `home.file` entry and the gate below hang off this.
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

        # Both tools resolve declarations through a `node_modules` that has to
        # sit inside the project, and the store copy is read-only. The link is
        # forced because a `path:` flake reference copies the gitignored one the
        # devshell leaves in the checkout, while a git reference does not.
        cp -R ${./extensions} ./extensions
        chmod -R u+w ./extensions
        ln -sfn ${dotfilesPackages.pi-extension-types}/node_modules ./extensions/node_modules

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

  # Pi's subagents run in-process, so anything exported here reaches them and
  # every command they shell out to. `JJ_EDITOR=false` turns a jj command that
  # wants an editor into an immediate failure the agent can read and correct;
  # unset, it opens one and the session hangs on a prompt nobody will answer.
  # Setting it in the shell environment instead would take the user's own
  # interactive `jj describe` with it, so it is scoped to pi here.
  pi-wrapped = pkgs.writeShellApplication {
    name = "pi";
    text = ''
      export JJ_EDITOR=false
      exec ${dotfilesPackages.pi}/bin/pi "$@"
    '';
  };

  nono-pi = mkNonoWrapper {
    name = "pi";
    profile = "coding-agents";
    command = "${pi-wrapped}/bin/pi";
  };
in
{
  imports = [ ../../lib/source.nix ];

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
      # Subagents as a first-class pi feature: agent definitions in
      # `agents/*.md`, an `Agent` tool to dispatch them, and a `/agents` menu.
      # Replaces a local extension that spawned a child pi over its JSON stream.
      "npm:@tintinweb/pi-subagents@0.18.2"

      # Pi has no MCP support of its own; this adds it. The shared agent module
      # delivers Exa through `~/.agents/mcp.json`, which the adapter treats as a
      # read-only input while keeping pi-specific overrides writable under
      # `~/.pi/agent/mcp.json` and project `.pi/mcp.json` files.
      "npm:pi-mcp-adapter@2.27.0"
    ];

    assertions = [
      {
        assertion = duplicatePiSkillNames == [ ];
        message = "pi-local skill(s) shadow the shared registry: ${lib.concatStringsSep ", " duplicatePiSkillNames}";
      }
    ];

    home = {
      packages = [
        pi-wrapped
        nono-pi
      ];

      extraBuilderCommands = ''
        mkdir -p $out/state
        ln -s ${packagesFile} $out/${packagesStatePath}

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

        # Pi auto-discovers `<dir>/index.ts` under this directory, so a new
        # extension needs no registration. Delivering through `mkSource` keeps
        # editable checkouts live-editable and writes no path into settings.json.
        ".pi/agent/extensions" = lib.mkIf hasPiExtensions { source = mkSource ./extensions; };
        ".pi/agent/skills" = renderPiSkillsDir { };

        # Agent definitions and the policy around them. Settings are safe to own
        # from here because pi-subagents only ever writes the project copy under
        # `.pi/`. Definitions are Nix-owned in the stronger sense that they are
        # store files: `/agents` edits, disables, and deletes the file it loaded
        # an agent from, so those actions fail on these. Overriding one means a
        # project definition of the same name under `.pi/agents/`.
        ".pi/agent/agents".source = ./agents;
        ".pi/agent/subagents.json".source = ./subagents.json;
      };
    };
  };
}
