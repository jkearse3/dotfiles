{
  config,
  pkgs,
  lib,
  self,
  llmAgents,
  repoRoot,
  editable,
  ...
}:
let
  mkSource = import ../../mkSource.nix {
    inherit
      config
      self
      lib
      repoRoot
      editable
      ;
  };
  renderSharedSkills = import ../renderSharedSkills.nix { inherit lib mkSource; };
  renderSharedRules = import ../renderSharedRules.nix { inherit lib mkSource; };
  claude-wrapped = pkgs.symlinkJoin {
    name = "claude-code-wrapped";
    paths = [
      llmAgents.claude-code
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
in
{
  home.packages = [
    claude-wrapped
    llmAgents.ccusage
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
    ".claude/statusline.sh".source = mkSource ./statusline.sh;
    ".claude/detect-vcs.sh".source = mkSource ./detect-vcs.sh;
  }
  // renderSharedRules ".claude/rules" [
    {
      name = "shared";
      sources = config.agents.sharedRules;
    }
    {
      name = "claude";
      sources = config.agents.claudeRules;
    }
  ]
  // renderSharedSkills ".claude/skills" config.agents.sharedSkills;
}
