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
  renderSkillsDir = import ../renderSkillsDir.nix {
    inherit lib pkgs;
    skills = config.agents.skills;
  };
  renderAgentsMarkdown = import ../renderAgentsMarkdown.nix { inherit lib; };
  preventIdleSleep = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin "/usr/bin/caffeinate -i ";

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
    ../../lib/source.nix
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
    ".claude/settings.json".source = mkSource ./settings.json;
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
    ".claude/statusline.sh".source = mkSource ./statusline.sh;

    # The sandboxed `nono-claude` wrapper inherits claude's static fish-shipped completion via
    # `--wraps`. claude.fish is pure `complete -c claude` declarations with no binary invocation,
    # so this adds completion for the wrapper name at no runtime cost. Autoloaded by command name.
    ".config/fish/completions/nono-claude.fish".text = ''
      complete -c nono-claude --wraps claude
    '';
  };
}
