{
  config,
  editable,
  herdr,
  herdrSource,
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
  completions = pkgs.runCommand "herdr-completions" { } ''
    mkdir -p $out/share/fish/vendor_completions.d $out/share/zsh/site-functions
    ${herdr}/bin/herdr completion fish > $out/share/fish/vendor_completions.d/herdr.fish
    ${herdr}/bin/herdr completion zsh > $out/share/zsh/site-functions/_herdr
  '';
  skill = pkgs.linkFarm "herdr-skill" [
    {
      name = "SKILL.md";
      path = herdrSource + "/SKILL.md";
    }
  ];
in
{
  home.packages = [
    herdr
    completions
  ];
  home.file.".config/herdr/config.toml".source = mkSource ./config.toml;
  agents.extraSkills.herdr = skill;
}
