{
  config,
  editable,
  llmAgents,
  pkgs,
  repoRoot,
  self,
  ...
}:
let
  mkSource = import ../../mkSource.nix {
    inherit
      config
      editable
      repoRoot
      self
      ;
    inherit (pkgs) lib;
  };
  herdrCompletions = pkgs.runCommand "herdr-completions" { } ''
    mkdir -p $out/share/fish/vendor_completions.d $out/share/zsh/site-functions
    ${llmAgents.herdr}/bin/herdr completion fish > $out/share/fish/vendor_completions.d/herdr.fish
    ${llmAgents.herdr}/bin/herdr completion zsh > $out/share/zsh/site-functions/_herdr
  '';
in
{
  home.packages = [
    llmAgents.herdr
    herdrCompletions
  ];
  home.file.".config/herdr/config.toml".source = mkSource ./config.toml;
}
