{
  inputs,
  withSystem,
}:
blueprint:
let
  home-manager = inputs.home-manager-unstable;
  llmAgents = inputs.llm-agents.packages;
  herdrRelease = builtins.fromJSON (
    builtins.readFile (inputs.llm-agents + "/packages/herdr/hashes.json")
  );
  editable = builtins.getEnv "DOTFILES_HOME_LOCKED" == "";
in
withSystem blueprint.system (
  {
    unstablePkgs,
    ...
  }:
  home-manager.lib.homeManagerConfiguration {
    pkgs = unstablePkgs;
    modules = [
      {
        home = {
          username = blueprint.user.name;
          inherit (blueprint.user) homeDirectory;
          inherit (blueprint.home) stateVersion;
        };
        programs.home-manager.enable = true;
        xdg.enable = true;
        xdg.configFile."dotfiles/blueprint-id".text = "${blueprint.blueprintId}\n";
        targets.darwin.copyApps.enable = false;
        programs.man.generateCaches = false;
      }
      blueprint.home.module
    ];
    extraSpecialArgs = {
      inherit editable;
      inherit (inputs) self;
      internalPkgs = inputs.self.packages.${blueprint.system};
      repoRoot = "dotfiles";
      llmAgents = llmAgents.${blueprint.system};
      herdr = llmAgents.${blueprint.system}.herdr;
      herdrSource = unstablePkgs.fetchFromGitHub {
        owner = "ogulcancelik";
        repo = "herdr";
        tag = "v${herdrRelease.version}";
        inherit (herdrRelease) hash;
      };
      hunk = llmAgents.${blueprint.system}.hunk;
    };
  }
)
