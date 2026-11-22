{
  inputs,
  withSystem,
}:
blueprint:
let
  home-manager = inputs.home-manager-unstable;
  homeManagerBaselineModule = {
    home = {
      username = blueprint.user.name;
      inherit (blueprint.user) homeDirectory;
      inherit (blueprint.home) stateVersion;
    };
    programs.home-manager.enable = true;
    xdg.enable = true;
    xdg.configFile."dotfiles/blueprint-id".text = "${blueprint.blueprintId}\n";
  };
in
withSystem blueprint.system (
  {
    config,
    system,
    unstablePkgs,
    ...
  }:
  let
    llmAgents = inputs.llm-agents.packages.${system};

    # OpenCode 2 installed as `bin/opencode` wrapping `bin/.opencode-wrapped`,
    # the layout of the OpenCode 1 package, so the program and its process keep
    # the names tools already know. Upstream installs it as `opencode2` to
    # coexist with v1. Upstream's install check runs `meta.mainProgram`, so a
    # rename that misses fails the build.
    opencode = llmAgents.opencode2.overrideAttrs (old: {
      installPhase =
        builtins.replaceStrings [ "$out/bin/opencode2" ] [ "$out/bin/opencode" ]
          old.installPhase;
      postFixup =
        builtins.replaceStrings [ "/bin/.opencode2-wrapped" ] [ "/bin/.opencode-wrapped" ]
          old.postFixup;
      meta = old.meta // {
        mainProgram = "opencode";
      };
    });
  in
  home-manager.lib.homeManagerConfiguration {
    pkgs = unstablePkgs;
    modules = [
      homeManagerBaselineModule
      blueprint.home.module
    ];
    extraSpecialArgs = {
      dotfilesPackages = config.packages // {
        inherit (llmAgents)
          ccusage
          claude-code
          herdr
          hunk
          pi
          ;
        inherit opencode;
      };
      dotfilesUser = blueprint.user;
      # The binary cache settings that `flake.nix` declares, so the home
      # configuration can offer them to plain `nix` commands.
      dotfilesNixConfig = (import ../../flake.nix).nixConfig;
    };
  }
)
