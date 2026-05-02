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
    ".config/opencode/agents".source = mkSource ./agents;
  };
}
