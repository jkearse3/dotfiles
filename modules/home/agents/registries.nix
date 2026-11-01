{ config, lib, ... }:
let
  localSkillSources = lib.mapAttrs (name: _: ./skills/${name}) (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./skills)
  );
  duplicateSkillNames = lib.intersectLists (lib.attrNames localSkillSources) (
    lib.attrNames config.agents.extraSkills
  );
in
{
  options.agents = {
    extraSkills = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = ''
        Extra skill directories made available to agent frontends, in addition to
        local skills discovered from `modules/home/agents/skills`.

        Each producer assigns a path directly
        (`agents.extraSkills.foo = ./bar;`).

        Skill names must be unique across extra-skill producers; defining the same
        name in two modules with different sources fails evaluation during normal
        Nix option merging. Extra skill names must also not duplicate local skill
        directory names.
      '';
    };

    skills = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      readOnly = true;
      description = ''
        Composed skill directories for agent frontends. Local skills are discovered
        from `modules/home/agents/skills`; external modules contribute through
        `agents.extraSkills`.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = duplicateSkillNames == [ ];
        message = "agents.extraSkills duplicates local skill(s): ${lib.concatStringsSep ", " duplicateSkillNames}";
      }
    ];

    agents.skills = localSkillSources // config.agents.extraSkills;
  };
}
