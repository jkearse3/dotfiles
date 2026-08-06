{ config, lib, ... }:
let
  localSkillSources = lib.mapAttrs (name: _: ./skills/${name}) (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./skills)
  );
  duplicateSkillNames = lib.intersectLists (lib.attrNames localSkillSources) (
    lib.attrNames config.agents.extraSkills
  );

  autoRegisterRules =
    dir:
    lib.mapAttrs'
      (name: _: {
        name = lib.removeSuffix ".md" name;
        value = dir + "/${name}";
      })
      (
        lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".md" name) (builtins.readDir dir)
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

    sharedRules = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = ''
        Markdown rule files auto-registered from `modules/home/agents/rules`,
        keyed by file name without the `.md` suffix. Stitched agent instruction
        files select rules by the `shared/<name>` IDs listed in
        `agents.sharedRuleOrder`; source paths should point at Markdown files.

        Producers may also assign a path directly
        (`agents.sharedRules.foo = ./bar.md;`).

        Rule names must be unique; defining the same name in two modules with
        different sources fails evaluation during normal Nix option merging.

        Rule load order comes from `agents.sharedRuleOrder`, which every
        stitched consumer passes; the registry itself does not order rules. A
        registered rule that the order omits is silently dropped.
      '';
    };
    sharedRuleOrder = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "shared/communication"
        "shared/reasoning"
        "shared/scope-alignment"
        "shared/version-control"
        "shared/mutation-safety"
      ];
      description = ''
        Fully qualified shared rule IDs in the order used by stitched agent
        instruction files.
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

    agents = {
      skills = localSkillSources // config.agents.extraSkills;
      sharedRules = autoRegisterRules ./rules;
    };
  };
}
