{
  agentInteractivePolicy,
  config,
  dotfilesPackages,
  pkgs,
  lib,
  mkNonoWrapper,
  mkSecretEnvironmentWrapper,
  mkSource,
  ...
}:
let
  renderAgentsMarkdown = import ../renderAgentsMarkdown.nix { inherit lib; };
  renderSkillsDir = import ../renderSkillsDir.nix {
    inherit lib pkgs;
    skills = config.agents.skills;
  };
  preventIdleSleep = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin "/usr/bin/caffeinate -i ";

  # caffeinate stays outermost so its idle-sleep assertion covers the whole
  # session, and secret resolution stays inside it but outside any sandbox.
  mkOpencode =
    {
      name,
      command,
    }:
    let
      secretEnvironment = mkSecretEnvironmentWrapper {
        name = "${name}-secret-environment";
        environmentName = "opencode";
        inherit command;
      };
    in
    pkgs.writeShellApplication {
      inherit name;
      text = ''
        ${agentInteractivePolicy.shellExports}
        exec ${preventIdleSleep}${lib.getExe secretEnvironment} "$@"
      '';
    };

  opencodeFishCompletion = # fish
    ''
      function __fish_opencode_completions
          set -l tokens (commandline --current-process --tokenize --cut-at-cursor)
          if string match -qr '\s$' -- (commandline --current-process --cut-at-cursor)
              set tokens $tokens ""
          end
          ${opencode-wrapped}/bin/opencode --get-yargs-completions $tokens 2>/dev/null \
              | string match -v -r '^\$0:' \
              | string replace -r '^([^:]+):(.*)$' '$1\t$2'
      end
      complete -c opencode -f -k -a '(__fish_opencode_completions)'
    '';

  opencode-wrapped = pkgs.symlinkJoin {
    name = "opencode-wrapped";
    paths = [
      dotfilesPackages.opencode
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

  nono-opencode-entrypoint = mkNonoWrapper {
    name = "opencode-entrypoint";
    profile = "coding-agents";
    command = "${opencode-wrapped}/bin/opencode";
  };

  opencode = mkOpencode {
    name = "opencode";
    command = "${opencode-wrapped}/bin/opencode";
  };
  nono-opencode = mkOpencode {
    name = "nono-opencode";
    command = "${nono-opencode-entrypoint}/bin/nono-opencode-entrypoint";
  };
in
{
  imports = [
    ../../lib/source.nix
    ../../nono
    ../../secrets
    ../registries.nix
  ];

  config = {
    home.packages = [
      opencode
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
      # `--wraps`. That completion calls the `opencode-wrapped` binary directly, not the secret or
      # caffeinate launcher, so tabbing never resolves secrets or launches the sandbox. Autoloaded by
      # command name, so it lives in its own file.
      ".config/fish/completions/nono-opencode.fish".text = ''
        complete -c nono-opencode --wraps opencode
      '';
    };
  };
}
