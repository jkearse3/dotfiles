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
  mkSource = import ../mkSource.nix {
    inherit
      config
      self
      lib
      repoRoot
      editable
      ;
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
        --set OPENCODE_DISABLE_LSP_DOWNLOAD 1
    '';
  };
in
{
  home.packages = [
    opencode-wrapped
  ];
  home.file = {
    ".config/opencode/opencode.jsonc".source = mkSource ./opencode.jsonc;
    ".config/opencode/tui.json".source = mkSource ./tui.json;
    ".config/fish/completions/opencode.fish".text = opencodeFishCompletion;
  };
}
