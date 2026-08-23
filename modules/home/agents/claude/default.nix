# Claude Code asset delivery: the wrapper, the settings pin, and the files
# rendered into `~/.claude`. See `pinnedSettingsPath` for why settings reach
# Claude Code as a flag rather than as a file in the home directory, and
# `settings-overlay.sh` for how the machine-local file overrides the pin.
{
  config,
  dotfilesPackages,
  pkgs,
  lib,
  mkNonoWrapper,
  ...
}:
let
  renderSkillsDir = import ../renderSkillsDir.nix {
    inherit lib pkgs;
    skills = config.agents.skills;
  };
  renderAgentsMarkdown = import ../renderAgentsMarkdown.nix { inherit lib; };
  preventIdleSleep = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin "/usr/bin/caffeinate -i ";

  pinnedSettings = builtins.fromJSON (builtins.readFile ./settings.json);

  # Every path the pin carries, with the value at it. The walk descends into
  # objects only: Claude Code unions arrays across layers and merges objects
  # leaf by leaf, so neither can be weakened from below and neither needs
  # classifying. Scalars are the entire surface a machine-local file can take
  # over.
  pinnedEntries =
    let
      walk =
        path: value:
        lib.optional (path != [ ]) { inherit path value; }
        ++ lib.optionals (builtins.isAttrs value) (
          lib.concatLists (lib.mapAttrsToList (name: walk (path ++ [ name ])) value)
        );
    in
    walk [ ] pinnedSettings;

  pinnedScalarPaths = map (entry: lib.concatStringsSep "." entry.path) (
    lib.filter (entry: !(builtins.isAttrs entry.value || builtins.isList entry.value)) pinnedEntries
  );

  # Paths reach the overlay dot-joined, so a settings key containing a dot would
  # encode ambiguously and could delete the wrong path. No Claude Code key
  # carries one today; if one ever does, switch the argv encoding to JSON rather
  # than special-case the key.
  dottedPinnedKeys = lib.filter (lib.hasInfix ".") (lib.concatMap (entry: entry.path) pinnedEntries);

  # The pinned scalars the machine may not take over, because each grants
  # capability rather than expressing a preference and `~/.claude/settings.json`
  # is writable from inside the `coding-agents` sandbox. Handing
  # `permissions.defaultMode` over would let an agent select `bypassPermissions`
  # for the next launch. `statusLine.command` is worse: Claude Code runs it as a
  # shell command on every refresh, gated on workspace trust alone rather than
  # on any permission rule, so a machine-local write would execute at the next
  # launch — outside the sandbox, since the plain `claude` wrapper is not
  # sandboxed. Enforcing it also keeps the pin agreeing with the
  # `~/.claude/statusline.sh` delivered below, which is why eval fails when it
  # goes missing.
  #
  # `permissions` needs no entry beyond `defaultMode`: its `allow`, `deny`,
  # `ask`, and `additionalDirectories` are arrays, which a machine can only add
  # to. `statusLine.type` stays overridable because it only turns the pinned
  # command on or off.
  #
  # Enforcement reaches only leaves the pin carries. A capability leaf it
  # does not pin — `apiKeyHelper`, an `env` entry — falls through to the
  # machine-local file like any unpinned leaf, and entries a machine appends
  # to `permissions.allow` or `additionalDirectories` take effect under
  # array union. No settings layer can close those additive channels,
  # `policySettings` included, because union and per-leaf merge only ever
  # add; a sandbox rule on the file could, at the cost of its role as the
  # runtime-write target. That residue is accepted.
  enforcedPaths = [
    "permissions.defaultMode"
    "statusLine.command"
  ];

  # Pinned scalars the overlay hands to the machine-local file once that file
  # defines them, so the pinned value is a default rather than a ceiling. These
  # are preferences only: none of them widens what Claude Code is allowed to do
  # or gets anything executed, which is the bar to clear before a path lands
  # here, because `~/.claude/settings.json` is writable from inside the sandbox.
  machineOverridablePaths = [
    "agentPushNotifEnabled"
    "attribution.commit"
    "attribution.pr"
    "attribution.sessionUrl"
    "autoMemoryEnabled"
    "disableAgentView"
    "editorMode"
    "effortLevel"
    "model"
    "promptSuggestionEnabled"
    "skipAutoPermissionPrompt"
    "statusLine.type"
    "theme"
    "tui"
    "verbose"
  ];

  # A typo demotes an enforced path to a silent fall-through, and eval is the
  # only place that can catch it.
  missingEnforcedPaths = lib.filter (
    path: !(lib.hasAttrByPath (lib.splitString "." path) pinnedSettings)
  ) enforcedPaths;

  # Pinning a scalar without classifying it would decide by default that the
  # machine may override it, which is the wrong default for a scalar that grants
  # capability rather than expressing a preference — a future `apiKeyHelper` or
  # a `defaultMode` sibling would hand over silently. Force the classification
  # at eval instead.
  #
  # `$schema` is an editor annotation rather than a setting, so it is exempt: it
  # stays in the payload and Claude Code ignores it either way. It could not join
  # `machineOverridablePaths` even so, because that list is interpolated into the
  # launch wrapper and shellcheck rejects the resulting `'$schema'` as SC2016 —
  # as it would any future key carrying a `$` or a backtick.
  unclassifiedPinnedPaths = lib.subtractLists (
    enforcedPaths ++ machineOverridablePaths ++ [ "$schema" ]
  ) pinnedScalarPaths;

  contradictoryPinnedPaths = lib.intersectLists enforcedPaths machineOverridablePaths;

  pinnedPermissionRules = lib.concatMap (behavior: pinnedSettings.permissions.${behavior} or [ ]) [
    "allow"
    "deny"
    "ask"
  ];

  # `Read` and `Edit` rule contents are the only ones Claude Code resolves as
  # paths, and a lone leading slash anchors them at the directory holding the
  # settings file they came from — which under the pin is a Nix store directory,
  # or nothing at all once the overlay passes the payload as a JSON string. The
  # `//`, `~/`, and bare-relative forms all anchor somewhere independent of that
  # file, so the single-slash form is the only one to reject.
  storeAnchoredRules = lib.filter (
    rule: builtins.match "(Read|Edit)\\(/([^/].*)?\\)" rule != null
  ) pinnedPermissionRules;

  # Claude Code resolves `--settings` at `flagSettings` precedence, above user,
  # project, and project-local settings. Resolution is per leaf rather than per
  # top-level key: nested objects merge leaf by leaf across layers, and arrays
  # union. A leaf absent from this file therefore falls through to
  # `~/.claude/settings.json`, which is left unmanaged, machine-local, and
  # writable, so runtime writes (`/model`, `/config`, user-scope permission
  # grants) land there instead of in this repository's working tree.
  #
  # Because arrays union, a machine can only add to `allow`, `deny`, `ask`, and
  # `additionalDirectories`, never remove from them, and a `deny` or `ask`
  # pinned here beats an `allow` from a lower-precedence source. The pinned
  # rules are therefore unweakenable without any help from the overlay.
  #
  # A leaf pinned here would otherwise shadow the machine-local file with no
  # indication in the UI: `/config` and `/model` still change the running
  # session and still report success, but what they persist lands in the
  # shadowed file and is gone at the next launch. `settings-overlay.sh` resolves
  # that for every path in `machineOverridablePaths`, leaving the pinned value
  # as a default that a machine-local write replaces. Making an enforced path
  # stick still means editing `settings.json` and running a Home Manager switch.
  #
  # Precedence, per-leaf resolution, and array unioning are undocumented Claude
  # Code internals, measured against 2.1.238 on 2026-08-23. Re-measure them
  # whenever the `llm-agents` input bumps `claude-code`.
  pinnedSettingsPath =
    assert lib.assertMsg (missingEnforcedPaths == [ ])
      "claude settings.json is missing enforced paths: ${lib.concatStringsSep ", " missingEnforcedPaths}";
    assert lib.assertMsg (dottedPinnedKeys == [ ])
      "claude settings.json pins keys containing a dot, which the overlay's dot-joined path encoding cannot express; switch that encoding to JSON before pinning them: ${lib.concatStringsSep ", " dottedPinnedKeys}";
    assert lib.assertMsg (storeAnchoredRules == [ ])
      "claude settings.json permission rules would anchor under the Nix store; use `//`, `~/`, or a working-directory-relative path: ${lib.concatStringsSep ", " storeAnchoredRules}";
    assert lib.assertMsg (unclassifiedPinnedPaths == [ ])
      "claude settings.json pins scalars that are neither enforced nor machine-overridable; add each to enforcedPaths or machineOverridablePaths: ${lib.concatStringsSep ", " unclassifiedPinnedPaths}";
    assert lib.assertMsg (contradictoryPinnedPaths == [ ])
      "claude settings paths are both enforced and machine-overridable: ${lib.concatStringsSep ", " contradictoryPinnedPaths}";
    ./settings.json;

  # Left unmanaged so Claude Code can write it, and read at launch to decide
  # which pinned keys step aside for this machine.
  machineSettingsPath = "${config.home.homeDirectory}/.claude/settings.json";

  settingsOverlay = pkgs.writeShellApplication {
    name = "claude-settings-overlay";
    runtimeInputs = [ pkgs.jq ];
    text = builtins.readFile ./settings-overlay.sh;
  };

  # The overlay decides what reaches `--settings`, so a regression there hands
  # over a key quietly rather than failing. Gate the script behind its fixtures
  # and hand the launch wrappers the checked path.
  checkedSettingsOverlay =
    pkgs.runCommandLocal "claude-settings-overlay-checked"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        bash ${./settings-overlay-test.sh} ${settingsOverlay}/bin/claude-settings-overlay
        ln -s ${settingsOverlay} "$out"
      '';

  claude-wrapped = pkgs.symlinkJoin {
    name = "claude-code-wrapped";
    paths = [
      dotfilesPackages.claude-code
    ];
    buildInputs = [
      pkgs.makeWrapper
    ];
    postBuild = ''
      wrapProgram $out/bin/claude \
        --set CLAUDE_CODE_DISABLE_BACKGROUND_TASKS 1 \
        --set CLAUDE_CONFIG_DIR ${config.home.homeDirectory}/.claude
    '';
  };

  # caffeinate stays outermost so its idle-sleep assertion covers the whole
  # session, wrapping both the direct binary and the sandbox entrypoint.
  mkClaude =
    {
      name,
      command,
    }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ checkedSettingsOverlay ];
      text = ''
        # `--settings` precedes "$@" so an explicit flag from the caller still
        # wins. That rests on one more undocumented behavior: a later
        # `--settings` occurrence displaces an earlier one entirely, rather
        # than the first winning or the two payloads merging per leaf. The
        # overlay absorbs an unusable machine-local file on its own;
        # the fallback here covers the overlay itself failing, which must not be
        # able to strand a launch without the pin.
        settings=$(claude-settings-overlay \
          ${pinnedSettingsPath} \
          ${lib.escapeShellArg machineSettingsPath} \
          ${lib.escapeShellArgs machineOverridablePaths}) || settings=${pinnedSettingsPath}

        exec ${preventIdleSleep}${command} --settings "$settings" "$@"
      '';
    };

  nono-claude-entrypoint = mkNonoWrapper {
    name = "claude-entrypoint";
    profile = "coding-agents";
    command = "${claude-wrapped}/bin/claude";
  };

  claude = mkClaude {
    name = "claude";
    command = "${claude-wrapped}/bin/claude";
  };
  nono-claude = mkClaude {
    name = "nono-claude";
    command = "${nono-claude-entrypoint}/bin/nono-claude-entrypoint";
  };
in
{
  imports = [
    ../../nono
    ../registries.nix
  ];

  home.packages = [
    claude
    nono-claude
    dotfilesPackages.ccusage
    (pkgs.writeShellScriptBin "claude-mcp-add-linear" ''
      exec claude mcp add linear-server -s local --transport http https://mcp.linear.app/mcp
    '')
  ];
  home.file = {
    # Claude's native binary mode checks for ~/.local/bin/claude on startup.
    # Since auto-update is disabled via llm-agents.nix wrapper, this path is unused.
    # Symlink to suppress the warning. It points at the launch wrapper rather
    # than the inner binary so that anything that does reach it still carries
    # the settings pin, which now lives in the wrapper rather than in flags
    # baked into `claude-wrapped`.
    ".local/bin/claude".source = "${claude}/bin/claude";

    # `.claude/settings.json` is deliberately absent: the pinned copy arrives
    # through the wrapper flag, leaving the home path free for Claude Code's
    # own runtime writes and for machine-local overrides of unenforced keys.

    ".claude/skills" = renderSkillsDir { };
    ".claude/CLAUDE.md".text = renderAgentsMarkdown {
      title = "Claude Code Instructions";
      registries = [
        {
          name = "shared";
          sources = config.agents.sharedRules;
        }
      ];
      order = config.agents.sharedRuleOrder;
    };
    # `statusLine.command` fails silently against a non-executable script, so
    # pin the bit rather than inheriting whatever mode the checkout carries.
    ".claude/statusline.sh" = {
      source = ./statusline.sh;
      executable = true;
    };

    # The sandboxed `nono-claude` wrapper inherits claude's static fish-shipped completion via
    # `--wraps`. claude.fish is pure `complete -c claude` declarations with no binary invocation,
    # so this adds completion for the wrapper name at no runtime cost. Autoloaded by command name.
    ".config/fish/completions/nono-claude.fish".text = ''
      complete -c nono-claude --wraps claude
    '';
  };
}
