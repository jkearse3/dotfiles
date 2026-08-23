# Claude Code asset delivery: the wrapper, the settings pin, and the files
# rendered into `~/.claude`. See `pinnedSettingsPath` for why settings reach
# Claude Code as a flag rather than as a file in the home directory.
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

  # Keys this module needs the pin to carry: `permissions` is what the pin
  # exists to enforce, and `statusLine` has to agree with the `statusline.sh`
  # delivered below. Every other key is a preference and may be dropped from the
  # pinned file to hand it back to the machine-local one.
  #
  # A typo demotes a key to a silent fall-through, and eval is the only place
  # that can catch it.
  missingPinnedKeys = lib.filter (key: !(pinnedSettings ? ${key})) [
    "permissions"
    "statusLine"
  ];

  pinnedPermissionRules = lib.concatMap (behavior: pinnedSettings.permissions.${behavior} or [ ]) [
    "allow"
    "deny"
    "ask"
  ];

  # `Read` and `Edit` rule contents are the only ones Claude Code resolves as
  # paths, and a lone leading slash anchors them at the directory holding the
  # settings file they came from — a Nix store directory under the pin. `//` is
  # filesystem-absolute, `~/` is home-rooted, and a bare relative pattern
  # follows the working directory, so only the single-slash form moves with the
  # source file.
  storeAnchoredRules = lib.filter (
    rule: builtins.match "(Read|Edit)\\(/([^/].*)?\\)" rule != null
  ) pinnedPermissionRules;

  # Claude Code resolves `--settings` at `flagSettings` precedence, above user,
  # project, and project-local settings. Resolution is per key, so a key absent
  # from this file still falls through to `~/.claude/settings.json`, which is
  # left unmanaged, machine-local, and writable: runtime writes (`/model`,
  # `/config`, user-scope permission grants) land there instead of in this
  # repository's working tree.
  #
  # Permission rules union across sources rather than replacing one another.
  # Rules pinned here add to project-local grants such as
  # `.claude/settings.local.json`, and a `deny` here overrides an `allow` from a
  # lower-precedence source.
  #
  # A key pinned here shadows the machine-local file with no indication in the
  # UI. `/config` and `/model` still change the running session, but what they
  # persist lands in the shadowed file, so the change is gone at the next launch
  # while both still report success. Making one stick means editing
  # `settings.json` and running a Home Manager switch.
  #
  # Precedence, per-key resolution, and rule unioning are undocumented Claude
  # Code internals verified against 2.1.238. Re-verify them whenever the
  # `llm-agents` input bumps `claude-code`.
  pinnedSettingsPath =
    assert lib.assertMsg (
      missingPinnedKeys == [ ]
    ) "claude settings.json is missing pinned keys: ${lib.concatStringsSep ", " missingPinnedKeys}";
    assert lib.assertMsg (storeAnchoredRules == [ ])
      "claude settings.json permission rules would anchor under the Nix store; use `//`, `~/`, or a working-directory-relative path: ${lib.concatStringsSep ", " storeAnchoredRules}";
    ./settings.json;

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
        --set CLAUDE_CONFIG_DIR ${config.home.homeDirectory}/.claude \
        --add-flags "--settings ${pinnedSettingsPath}"
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
      text = ''
        exec ${preventIdleSleep}${command} "$@"
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
    # Symlink to suppress the warning.
    ".local/bin/claude".source = "${claude-wrapped}/bin/claude";

    # `.claude/settings.json` is deliberately absent: the pinned copy arrives
    # through the wrapper flag, leaving the home path free for Claude Code's
    # own runtime writes.

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
