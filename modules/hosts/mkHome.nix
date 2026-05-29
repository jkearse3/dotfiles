{
  inputs,
  withSystem,
}:
{
  hostname,
  username,
  system,
  extraHomeModules ? [ ],
}:
assert builtins.elem system [
  "aarch64-darwin"
  "x86_64-darwin"
  "aarch64-linux"
  "x86_64-linux"
];
let
  lib = inputs.nixpkgs.lib;
  home-manager = inputs.home-manager-unstable;
  llmAgents = inputs.llm-agents.packages;
  homeStateVersion = "26.05";
  isDarwin = lib.hasSuffix "-darwin" system;
  homeDirectory = if isDarwin then "/Users/${username}" else "/home/${username}";
  editable = builtins.getEnv "DOTFILES_HOME_LOCKED" == "";
in
{
  flake.homeConfigurations."${username}@${hostname}" = withSystem system (
    {
      unstablePkgs,
      ...
    }:
    home-manager.lib.homeManagerConfiguration {
      pkgs = unstablePkgs;
      modules = [
        (
          {
            home = {
              inherit username homeDirectory;
              stateVersion = homeStateVersion;
            };
            programs.home-manager.enable = true;
            xdg.enable = true;
          }
          // lib.optionalAttrs isDarwin {
            targets.darwin.copyApps.enable = false;
          }
        )
        ../home
      ]
      ++ extraHomeModules;
      extraSpecialArgs = {
        inherit editable;
        inherit (inputs) self;
        repoRoot = "dotfiles";
        llmAgents = llmAgents.${system};
        hunk = llmAgents.${system}.hunk;
      };
    }
  );
}
