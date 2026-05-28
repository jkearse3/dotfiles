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
  renderSharedSkills = import ./renderSharedSkills.nix { inherit lib mkSource; };
  renderSharedRules = import ./renderSharedRules.nix { inherit lib mkSource; };

  mkRuleRegistryOption =
    registryName:
    lib.mkOption {
      # A list of source paths per rule name so module-merge concatenates rather
      # than silently picking one definition. `apply` collapses each list back to
      # a single path, throwing a named error when two definitions register the
      # same rule name with different sources.
      type = lib.types.attrsOf (lib.types.listOf lib.types.path);
      default = { };
      description = ''
        Markdown rule files for the ${registryName} registry. Rendered rule names
        are installed as `<target>/<name>.md`; source paths must end in `.md`.

        Each producer assigns a singleton list of paths
        (`agents.${registryName}Rules.foo = [ ./bar.md ];`). The list type is what
        drives module-merge-based duplicate detection: two definitions for the
        same rule name concatenate into a multi-element list, which `apply` then
        rejects.

        Rule names must be unique within this registry; defining the same name in
        two modules with different sources fails evaluation with an
        `agents.${registryName}Rules: duplicate rule name` error. Rendered target
        directories also reject rule-name collisions across registries.

        Intra-directory rule load order is implementation-defined by each agent
        loader and is not guaranteed by the registry.
      '';
      # `apply` is forced eagerly over every key below so a future consumer that
      # reads only a subset of the attrset cannot silently bypass the duplicate
      # check for unread keys.
      apply =
        sources:
        let
          resolved = lib.mapAttrs (
            name: srcs:
            if lib.length srcs == 1 then
              lib.head srcs
            else
              throw "agents.${registryName}Rules: duplicate rule name '${name}' registered by ${toString (lib.length srcs)} definitions: ${
                lib.concatMapStringsSep ", " toString srcs
              }"
          ) sources;
        in
        lib.deepSeq (lib.attrValues resolved) resolved;
    };
  autoRegisterRules =
    dir:
    lib.mapAttrs'
      (name: _: {
        name = lib.removeSuffix ".md" name;
        value = [ (dir + "/${name}") ];
      })
      (
        lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".md" name) (builtins.readDir dir)
      );
in
{
  imports = [
    ./claude
    ./opencode
  ];

  options.agents.sharedSkills = lib.mkOption {
    # A list of source paths per skill name so module-merge concatenates rather
    # than silently picking one definition. `apply` collapses each list back to
    # a single path, throwing a named error when two definitions register the
    # same skill name with different sources.
    type = lib.types.attrsOf (lib.types.listOf lib.types.path);
    default = { };
    description = ''
      Skill directories shared across agent frontends. Each entry renders into
      both `~/.agents/skills/<name>` and `~/.claude/skills/<name>` via the
      `renderSharedSkills` helper.

      Each producer assigns a singleton list of paths
      (`agents.sharedSkills.foo = [ ./bar ];`). The list type is what drives
      module-merge-based duplicate detection: two definitions for the same
      skill name concatenate into a multi-element list, which `apply` then
      rejects.

      Skill names must be unique across producers; defining the same name in
      two modules with different sources fails evaluation with an
      `agents.sharedSkills: duplicate skill name` error.
    '';
    # `apply` is forced eagerly over every key below so a future consumer that
    # reads only a subset of the attrset cannot silently bypass the duplicate
    # check for unread keys.
    apply =
      sources:
      let
        resolved = lib.mapAttrs (
          name: srcs:
          if lib.length srcs == 1 then
            lib.head srcs
          else
            throw "agents.sharedSkills: duplicate skill name '${name}' registered by ${toString (lib.length srcs)} definitions: ${
              lib.concatMapStringsSep ", " toString srcs
            }"
        ) sources;
      in
      lib.deepSeq (lib.attrValues resolved) resolved;
  };

  options.agents.sharedRules = mkRuleRegistryOption "shared";
  options.agents.claudeRules = mkRuleRegistryOption "claude";
  options.agents.opencodeRules = mkRuleRegistryOption "opencode";

  config = {
    agents.sharedSkills = lib.mapAttrs (name: _: [ ./skills/${name} ]) (
      lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./skills)
    );
    agents.sharedRules = autoRegisterRules ./rules;
    agents.claudeRules = autoRegisterRules ./claude/rules;
    agents.opencodeRules = autoRegisterRules ./opencode/rules;

    home.file =
      renderSharedRules ".agents/rules" [
        {
          name = "shared";
          sources = config.agents.sharedRules;
        }
      ]
      // renderSharedSkills ".agents/skills" config.agents.sharedSkills;
  };
}
