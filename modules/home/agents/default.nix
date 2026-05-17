{
  config,
  lib,
  self,
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
in
{
  imports = [
    ./claude
    ./opencode
  ];

  options.agents.skillSources = lib.mkOption {
    type = lib.types.attrsOf lib.types.path;
    default = { };
    description = "Skill directories to deploy into .agents/skills.";
  };

  config = {
    agents.skillSources = lib.mapAttrs (name: _: ./skills/${name}) (
      lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./skills)
    );

    home.file = {
      ".agents/rules".source = mkSource ./rules;
    }
    // lib.mapAttrs' (name: src: {
      name = ".agents/skills/${name}";
      value.source = mkSource src;
    }) config.agents.skillSources;
  };
}
