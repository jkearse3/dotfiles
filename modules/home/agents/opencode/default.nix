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
  renderRuleRegistries = import ../renderRuleRegistries.nix { inherit lib mkSource; };

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
        --set OPENCODE_DISABLE_LSP_DOWNLOAD 1
    '';
  };

  opencode-nono-entrypoint = pkgs.writeShellScript "opencode-nono-entrypoint" ''
    if [[ -z "''${NONO_OPENCODE_USE_PERMISSIONS:-}" ]]; then
      export OPENCODE_PERMISSION='{"*":"allow","bash":{"*":"allow"}}'
    fi
    exec "${opencode-wrapped}/bin/opencode" "$@"
  '';

  nono-opencode = mkNonoWrapper {
    name = "opencode";
    profile = "coding-agents";
    command = "${opencode-nono-entrypoint}";
  };
in
{
  home.packages = [
    opencode-wrapped
    nono-opencode
  ];
  home.file = {
    ".config/opencode/opencode.jsonc".source = mkSource ./opencode.jsonc;
    ".config/opencode/tui.json".source = mkSource ./tui.json;
    ".config/fish/completions/opencode.fish".text = opencodeFishCompletion;

    # The sandboxed `nono-opencode` wrapper inherits opencode's dynamic yargs completion via fish's
    # `--wraps`. The wrapped function calls the bare `opencode` binary, so tabbing never launches the
    # sandbox. Autoloaded by command name, so it lives in its own file.
    ".config/fish/completions/nono-opencode.fish".text = ''
      complete -c nono-opencode --wraps opencode
    '';
  }
  // renderRuleRegistries ".config/opencode/rules" [
    {
      name = "shared";
      sources = config.agents.sharedRules;
    }
    {
      name = "opencode";
      sources = config.agents.opencodeRules;
    }
  ];
}
