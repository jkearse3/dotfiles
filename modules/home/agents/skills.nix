# The agent skill registry: skill directories (a `SKILL.md` plus supporting
# files) that agent frontends install as skills. Add one either as a directory
# under `modules/home/agents/skills/`, which is discovered automatically, or
# from another module with `agents.extraSkills.<name> = <path>;`. Frontends
# install the composed set by reading `agents.skillsDir`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  localSkillSources = lib.mapAttrs (name: _: ./skills/${name}) (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./skills)
  );
  duplicateSkillNames = lib.intersectLists (lib.attrNames localSkillSources) (
    lib.attrNames config.agents.extraSkills
  );
  composedSkillSources = localSkillSources // config.agents.extraSkills;
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

        Contributed skills appear in `agents.skillsDir` alongside local skills.
      '';
    };

    skillsDir = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = ''
        Directory derivation `agent-skills` holding one symlink per composed
        skill: local skills discovered from `modules/home/agents/skills` plus
        `agents.extraSkills`. Agent frontends use it as the source of their
        skills `home.file` entry.
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

    agents.skillsDir = pkgs.linkFarm "agent-skills" (
      lib.mapAttrsToList (name: path: { inherit name path; }) composedSkillSources
    );
  };
}
