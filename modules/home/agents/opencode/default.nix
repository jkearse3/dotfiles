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

  opencode-wrapped = pkgs.symlinkJoin {
    name = "opencode-wrapped";
    paths = [
      dotfilesPackages.opencode
    ];
    buildInputs = [
      pkgs.makeWrapper
    ];
    # `OPENCODE_CONFIG_CONTENT` layers the `shell` key over the global config,
    # which stays a static file. Without it OpenCode takes `$SHELL`, and on
    # macOS replaces fish with `/bin/zsh`. `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS`
    # skips skills under `~/.claude/skills` and a project's `.claude/skills`,
    # which hold Claude-only skills, but keeps the `CLAUDE.md` instruction
    # fallback for projects without `AGENTS.md`. Only Nix updates OpenCode:
    # `OPENCODE_DISABLE_AUTOUPDATE` skips the update check even if the
    # `update: "disable"` setting in `opencode.jsonc` is lost.
    postBuild = ''
      wrapProgram $out/bin/opencode \
        --set OPENCODE_CONFIG_CONTENT ${
          lib.escapeShellArg (builtins.toJSON { shell = config.agents.shellPath; })
        } \
        --set OPENCODE_DISABLE_AUTOUPDATE 1 \
        --set OPENCODE_DISABLE_CLAUDE_CODE_SKILLS 1
    '';
  };

  # OpenCode prints a static fish completion script. The command creates its
  # log directory under `$HOME`, which the build sandbox leaves unwritable.
  opencodeFishCompletion = pkgs.runCommand "opencode-fish-completion" { } ''
    HOME=$(mktemp -d)
    ${dotfilesPackages.opencode}/bin/opencode --completions fish > $out
  '';

  opencodeLaunchers = mkAgentLaunchers {
    name = "opencode";
    command = "${opencode-wrapped}/bin/opencode";
    secretEnvironment = "opencode";
  };
in
{
  imports = [
    ../../nono
    ../../secrets
    ../skills.nix
    ../rules.nix
    ../shell.nix
  ];

  config = {
    home.packages = [
      opencodeLaunchers.launcher
      opencodeLaunchers.nonoLauncher
    ];
    home.file = {
      ".config/opencode/opencode.jsonc".source = ./opencode.jsonc;
      # OpenCode reads terminal settings such as the theme from `cli.json`. It
      # saves a setting changed inside OpenCode by renaming a new file over
      # `cli.json`, so `force` lets the next switch restore this content instead
      # of reporting a conflict.
      ".config/opencode/cli.json" = {
        source = ./cli.json;
        force = true;
      };
      # Without this, every OpenCode client joins one shared background service
      # and runs its tools in that service's process, outside the `nono-opencode`
      # sandbox. `opencode service set` replaces the link with a regular file,
      # which `force` lets the next switch restore.
      ".config/opencode/service.json" = {
        text = builtins.toJSON { disabled = true; };
        force = true;
      };
      ".config/opencode/skills" = {
        source = config.agents.skillsDir;
        recursive = true;
      };
      ".config/opencode/AGENTS.md".text = renderAgentsMarkdown {
        title = "OpenCode Instructions";
        registries = [
          {
            name = "shared";
            sources = config.agents.sharedRules;
          }
        ];
        order = config.agents.sharedRuleOrder;
      };
      ".config/fish/completions/opencode.fish".source = opencodeFishCompletion;

      # The sandboxed `nono-opencode` wrapper inherits opencode's completion via fish's `--wraps`.
      # The completion script is static and never runs opencode, so tabbing never resolves secrets
      # or launches the sandbox. Autoloaded by command name, so it lives in its own file.
      ".config/fish/completions/nono-opencode.fish".text = ''
        complete -c nono-opencode --wraps opencode
      '';
    };
  };
}
