{ lib, ... }:
let
  mkRuleRegistryOption =
    registryName:
    lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = ''
        Markdown rule files for the ${registryName} registry. Stitched agent
        instruction files select rules by registry-qualified IDs such as
        `${registryName}/<name>`; source paths should point at Markdown files.

        Each producer assigns a path directly
        (`agents.${registryName}Rules.foo = ./bar.md;`).

        Rule names must be unique within this registry; defining the same name in
        two modules with different sources fails evaluation during normal Nix
        option merging. The same bare rule name may appear in another registry
        because stitched consumers use registry-qualified IDs.

        Rule load order is controlled by each stitched instruction consumer, not
        by the registry itself.
      '';
    };

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
  options.agents.sharedSkills = lib.mkOption {
    type = lib.types.attrsOf lib.types.path;
    default = { };
    description = ''
      Skill directories shared across agent frontends. Each entry renders into
      both `~/.agents/skills/<name>` and `~/.claude/skills/<name>` via the
      `renderSharedSkills` helper.

      Each producer assigns a path directly
      (`agents.sharedSkills.foo = ./bar;`).

      Skill names must be unique across producers; defining the same name in two
      modules with different sources fails evaluation during normal Nix option
      merging.
    '';
  };

  options.agents.sharedRules = mkRuleRegistryOption "shared";
  options.agents.claudeRules = mkRuleRegistryOption "claude";
  options.agents.opencodeRules = mkRuleRegistryOption "opencode";
  options.agents.sharedRuleOrder = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [
      "shared/communication"
      "shared/reasoning"
      "shared/markdown"
      "shared/version-control"
      "shared/software-development"
    ];
    description = ''
      Fully qualified shared rule IDs in the order used by stitched agent
      instruction files.
    '';
  };

  config = {
    agents.sharedSkills = lib.mapAttrs (name: _: ./skills/${name}) (
      lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./skills)
    );
    agents.sharedRules = autoRegisterRules ./rules;
    agents.claudeRules = autoRegisterRules ./claude/rules;
    agents.opencodeRules = autoRegisterRules ./opencode/rules;
  };
}
