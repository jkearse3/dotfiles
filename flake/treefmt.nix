{
  perSystem =
    { config, ... }:
    let
      # Claude Code owns this file at runtime and rewrites it on its own
      # schedule, so prettier's array collapsing would be undone on every
      # settings write. `claude-settings-format` matches what Claude emits.
      claudeSettings = "modules/home/agents/claude/settings.json";
    in
    {
      treefmt = {
        projectRootFile = "flake.nix";
        programs = {
          nixfmt.enable = true;
          stylua.enable = true;
          shfmt = {
            enable = true;
            indent_size = 0;
          };
          taplo.enable = true;
          prettier.enable = true;
        };
        settings.formatter = {
          prettier.excludes = [ claudeSettings ];
          claude-settings-format = {
            command = "${config.packages.claude-settings-format}/bin/claude-settings-format";
            includes = [ claudeSettings ];
          };
        };
      };
    };
}
