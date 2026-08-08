{
  dotfilesPackages,
  mkSource,
  pkgs,
  ...
}:
let
  completions = pkgs.runCommand "herdr-completions" { } ''
    mkdir -p $out/share/fish/vendor_completions.d $out/share/zsh/site-functions
    ${dotfilesPackages.herdr}/bin/herdr completion fish > $out/share/fish/vendor_completions.d/herdr.fish
    ${dotfilesPackages.herdr}/bin/herdr completion zsh > $out/share/zsh/site-functions/_herdr
  '';
  skill = pkgs.runCommand "herdr-skill" { } ''
    mkdir -p $out
    ${dotfilesPackages.herdr}/bin/herdr --skill > $out/SKILL.md
    test -s $out/SKILL.md
  '';
in
{
  imports = [
    ../../agents/registries.nix
    ../../lib/source.nix
  ];

  home.packages = [
    dotfilesPackages.herdr
    completions
  ];
  home.file.".config/herdr/config.toml".source = mkSource ./config.toml;
  agents.extraSkills.herdr = skill;
}
