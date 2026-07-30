{
  inputs,
  withSystem,
}:
{
  blueprintId,
  os,
  username,
  system,
  extraHomeModules ? [ ],
  ...
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
  herdrRelease = builtins.fromJSON (
    builtins.readFile (inputs.llm-agents + "/packages/herdr/hashes.json")
  );
  homeStateVersion = "26.05";
  isDarwin = os == "darwin";
  homeDirectory = if isDarwin then "/Users/${username}" else "/home/${username}";
  editable = builtins.getEnv "DOTFILES_HOME_LOCKED" == "";
in
{
  flake.homeConfigurations."${username}@${blueprintId}" = withSystem system (
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
            xdg.configFile."dotfiles/blueprint-id".text = "${blueprintId}\n";
          }
          // lib.optionalAttrs isDarwin {
            targets.darwin.copyApps.enable = false;
            programs.man.generateCaches = false;
          }
        )
        ../home
      ]
      ++ extraHomeModules;
      extraSpecialArgs = {
        inherit editable;
        inherit (inputs) self;
        internalPkgs = inputs.self.packages.${system};
        repoRoot = "dotfiles";
        llmAgents = llmAgents.${system};
        herdr = llmAgents.${system}.herdr;
        herdrSource = unstablePkgs.fetchFromGitHub {
          owner = "ogulcancelik";
          repo = "herdr";
          tag = "v${herdrRelease.version}";
          inherit (herdrRelease) hash;
        };
        hunk = llmAgents.${system}.hunk;
      };
    }
  );
}
