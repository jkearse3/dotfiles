_:
let
  workstationHome = {
    imports = [
      ../modules/home
    ];
  };

  workstationDarwin = { };
in
{
  dotfiles.blueprints = {
    laptop-personal = {
      system = "aarch64-darwin";
      user = {
        name = "johnnie";
        homeDirectory = "/Users/johnnie";
      };
      home = {
        stateVersion = "26.05";
        module = {
          imports = [ workstationHome ];
          agents.opencode.sopsEnvironmentFile = ../secrets/personal/opencode.sops.yaml;
        };
      };
      darwin = {
        stateVersion = 5;
        module = workstationDarwin;
      };
    };

    laptop-lab = {
      system = "aarch64-darwin";
      user = {
        name = "johnnie";
        homeDirectory = "/Users/johnnie";
      };
      home = {
        stateVersion = "26.05";
        module = workstationHome;
      };
      darwin = {
        stateVersion = 5;
        module = workstationDarwin;
      };
    };
  };
}
