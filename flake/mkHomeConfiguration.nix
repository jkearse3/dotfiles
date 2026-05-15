{
  inputs,
  withSystem,
}:
blueprint:
let
  home-manager = inputs.home-manager-unstable;
  llmAgents = inputs.llm-agents.packages;
  useEditableHomeSources = builtins.getEnv "DOTFILES_HOME_LOCKED" == "";
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
    unstablePkgs,
    ...
  }:
  home-manager.lib.homeManagerConfiguration {
    pkgs = unstablePkgs;
    modules = [
      homeManagerBaselineModule
      blueprint.home.module
    ];
    extraSpecialArgs = {
      dotfilesPackages = inputs.self.packages.${blueprint.system} // {
        inherit (llmAgents.${blueprint.system})
          ccusage
          claude-code
          herdr
          hunk
          opencode
          pi
          ;
      };
      dotfilesSource = {
        root = inputs.self;
        repositoryDirectory = "dotfiles";
        editable = useEditableHomeSources;
      };
    };
  }
)
