{
  config,
  dotfilesPackages,
  lib,
  pkgs,
  ...
}:
let
  agentInteractivePolicy = import ./interactive-policy.nix {
    inherit lib pkgs;
    agentInteractiveDenied = dotfilesPackages.agent-interactive-denied;
    agentPolicy = dotfilesPackages.agent-policy;
  };
  agentLauncher = import ./launcher.nix {
    inherit lib pkgs;
    scratchSweep = dotfilesPackages.scratch-sweep;
    exitSweepIdleFor = config.agents.scratchSweep.exitIdleFor;
  };
  renderSkillsDir = import ./renderSkillsDir.nix {
    inherit lib pkgs;
    skills = config.agents.skills;
  };
in
{
  imports = [
    ./registries.nix
    ./shell.nix
    ./claude
    ./opencode
    ./pi
  ];

  options.agents.scratchSweep.exitIdleFor = lib.mkOption {
    type = lib.types.str;
    default = "0";
    example = "2h";
    description = ''
      Duration passed to `scratch-sweep clean --idle-for` when an agent launcher
      exits and sweeps its launch's temp root: `0`, or a whole number followed
      by `s`, `m`, `h` or `d`. Build output written within that duration is
      kept. The default `0` removes all of it, since no other agent uses the
      exiting launch's root.
    '';
  };

  config = {
    assertions = [
      {
        assertion = builtins.match "0|[0-9]+[smhd]" config.agents.scratchSweep.exitIdleFor != null;
        message = "agents.scratchSweep.exitIdleFor must be 0 or a whole number followed by s, m, h or d, not ${builtins.toJSON config.agents.scratchSweep.exitIdleFor}";
      }
    ];

    _module.args = {
      inherit agentInteractivePolicy agentLauncher;
    };

    home = {
      packages = [
        dotfilesPackages.agent-interactive-denied
        dotfilesPackages.scratch-sweep
        dotfilesPackages.token-count
        pkgs.tokscale
      ];

      extraBuilderCommands = ''
        mkdir -p $out/state
        ln -s ${agentInteractivePolicy.check} $out/state/agent-interactive-policy-checked
      '';

      file = {
        ".agents/mcp.json".source = ./mcp.json;
        ".agents/skills" = renderSkillsDir { };
      };
    };
  };
}
