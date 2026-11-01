# The shared rule registry: Markdown rules every stitched agent instruction file
# draws from, auto-registered from `modules/home/agents/rules` or contributed by
# other modules through `agents.sharedRules.<name>` (as `shell.nix` does), and
# the order those files load them in.
{ lib, ... }:
let
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
        "shared/shell-environment"
        "shared/communication"
        "shared/reasoning"
        "shared/delegation"
        "shared/version-control"
        "shared/build-copies"
        "shared/running-checks"
        "shared/mutation-safety"
        "shared/change-review"
      ];
      description = ''
        Fully qualified shared rule IDs in the order used by stitched agent
        instruction files.
      '';
    };
  };

  config.agents.sharedRules = autoRegisterRules ./rules;
}
