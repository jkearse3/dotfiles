_:
let
  workstationHome = {
    imports = [
      ../modules/home/agents
      ../modules/home/bash
      ../modules/home/build-deps
      ../modules/home/containers
      ../modules/home/gcp
      ../modules/home/go
      ../modules/home/hunk
      ../modules/home/javascript
      ../modules/home/jsonnet
      ../modules/home/kdl
      ../modules/home/lua
      ../modules/home/markdown
      ../modules/home/media
      ../modules/home/neovim
      ../modules/home/nix
      ../modules/home/nono
      ../modules/home/playwright-cli
      ../modules/home/protobuf
      ../modules/home/python
      ../modules/home/rust
      ../modules/home/secrets
      ../modules/home/shell
      ../modules/home/terminal
      ../modules/home/toml
      ../modules/home/vcs
      ../modules/home/yaml
    ];
  };

  workstationDarwin = {
    imports = [
      ../modules/darwin/determinate-nix.nix
      ../modules/darwin/homebrew.nix
      ../modules/darwin/security.nix
      ../modules/darwin/shell.nix
    ];
  };
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
