{
  config,
  pkgs,
  lib,
  self,
  llmAgents,
  mkNonoWrapper,
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
  renderAgentsMarkdown = import ../renderAgentsMarkdown.nix { inherit lib; };
  renderSkillsDir = import ../renderSkillsDir.nix {
    inherit lib pkgs;
    skills = config.agents.skills;
  };
  opencodeSecretsFile = "${config.xdg.configHome}/sops/secrets/opencode.sops.yaml";

  mkOpencodeWithSecrets =
    {
      name,
      command,
    }:
    pkgs.writeShellApplication {
      inherit name;
      text = ''
        printf -v command_string '%q ' ${lib.escapeShellArg command} "$@"
        exec ${lib.getExe pkgs.sops} exec-env --same-process \
          ${lib.escapeShellArg opencodeSecretsFile} "$command_string"
      '';
    };

  opencodeFishCompletion = # fish
    ''
      function __fish_opencode_completions
          set -l tokens (commandline --current-process --tokenize --cut-at-cursor)
          if string match -qr '\s$' -- (commandline --current-process --cut-at-cursor)
              set tokens $tokens ""
          end
          opencode --get-yargs-completions $tokens 2>/dev/null \
              | string match -v -r '^\$0:' \
              | string replace -r '^([^:]+):(.*)$' '$1\t$2'
      end
      complete -c opencode -f -k -a '(__fish_opencode_completions)'
    '';

  opencode-wrapped = pkgs.symlinkJoin {
    name = "opencode-wrapped";
    paths = [
      llmAgents.opencode
    ];
    buildInputs = [
      pkgs.makeWrapper
    ];
    postBuild = ''
      wrapProgram $out/bin/opencode \
        --set OPENCODE_DISABLE_AUTOUPDATE 1 \
        --set OPENCODE_ENABLE_EXA 1 \
        --set OPENCODE_DISABLE_EXTERNAL_SKILLS true \
        --set OPENCODE_DISABLE_LSP_DOWNLOAD 1
    '';
  };

  opencode-nono-entrypoint = pkgs.writeShellScript "opencode-nono-entrypoint" ''
    if [[ -z "''${NONO_OPENCODE_USE_PERMISSIONS:-}" ]]; then
      export OPENCODE_PERMISSION='{"*":"allow","question":"deny","bash":{"*":"allow"}}'
    fi
    exec "${opencode-wrapped}/bin/opencode" "$@"
  '';

  opencode-unsafe-entrypoint = pkgs.writeShellApplication {
    name = "opencode-unsafe-entrypoint";
    text = ''
      export OPENCODE_PERMISSION='{"*":"allow","question":"deny","bash":{"*":"allow"}}'
      exec "${opencode-wrapped}/bin/opencode" "$@"
    '';
  };

  nono-opencode-entrypoint = mkNonoWrapper {
    name = "opencode-entrypoint";
    profile = "coding-agents";
    command = "${opencode-nono-entrypoint}";
  };

  opencode = mkOpencodeWithSecrets {
    name = "opencode";
    command = "${opencode-wrapped}/bin/opencode";
  };
  opencode-unsafe = mkOpencodeWithSecrets {
    name = "opencode-unsafe";
    command = "${opencode-unsafe-entrypoint}/bin/opencode-unsafe-entrypoint";
  };
  nono-opencode = mkOpencodeWithSecrets {
    name = "nono-opencode";
    command = "${nono-opencode-entrypoint}/bin/nono-opencode-entrypoint";
  };
in
{
  home.packages = [
    opencode
    opencode-unsafe
    nono-opencode
  ];
  home.file = {
    ".config/opencode/opencode.jsonc".source = mkSource ./opencode.jsonc;
    ".config/opencode/tui.json".source = mkSource ./tui.json;
    ".config/opencode/skills" = renderSkillsDir { };
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
    ".config/fish/completions/opencode.fish".text = opencodeFishCompletion;

    # The sandboxed `nono-opencode` wrapper inherits opencode's dynamic yargs completion via fish's
    # `--wraps`. The wrapped function calls the bare `opencode` binary, so tabbing never launches the
    # sandbox. Autoloaded by command name, so it lives in its own file.
    ".config/fish/completions/nono-opencode.fish".text = ''
      complete -c nono-opencode --wraps opencode
    '';
    ".config/fish/completions/opencode-unsafe.fish".text = ''
      complete -c opencode-unsafe --wraps opencode
    '';
  };
  xdg.configFile."sops/secrets/opencode.sops.yaml".source = ./secrets.sops.yaml;
}
