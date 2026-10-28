{
  inputs,
  withSystem,
}:
blueprint:
let
  home-manager = inputs.home-manager-unstable;
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
    config,
    system,
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
      dotfilesPackages = config.packages // {
        inherit (inputs.llm-agents.packages.${system})
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
