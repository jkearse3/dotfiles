# Declares concrete blueprints and the reusable workstation composition modules
# they select. Output construction and validation live under `flake/`.
{ inputs, ... }:
let
  workstationHomeModule = {
    imports = [
      ../modules/home/agents
      ../modules/home/bash
      ../modules/home/build-deps
      ../modules/home/containers
      ../modules/home/database
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

    # Applications are managed outside Home Manager.
    targets.darwin.copyApps.enable = false;

    # Darwin lacks the Linux mandb tooling used to generate Home Manager caches.
    programs.man.generateCaches = false;
  };

  workstationDarwinModule = {
    imports = [
      ../modules/darwin/determinate-nix.nix
      ../modules/darwin/homebrew.nix
      ../modules/darwin/security.nix
      ../modules/darwin/shell.nix
    ];
  };
in
{
  # Each declaration is a complete activation contract. Identity and state
  # versions are repeated intentionally so blueprints can evolve independently;
  # policy shared across declarations belongs in the composition modules above.
  dotfiles.blueprintDeclarations = {
    laptop-personal = {
      system = "aarch64-darwin";
      user = {
        name = "johnnie";
        homeDirectory = "/Users/johnnie";
      };
      home = {
        stateVersion = "26.05";
        module = {
          imports = [ workstationHomeModule ];

          agents.opencode.sopsEnvironmentFile = ../secrets/personal/opencode.sops.yaml;
        };
      };
      darwin = {
        stateVersion = 5;
        module = workstationDarwinModule;
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
        module = {
          imports = [ workstationHomeModule ];
        };
      };
      darwin = {
        stateVersion = 5;
        module = workstationDarwinModule;
      };
    };

    laptop-work = {
      system = "aarch64-darwin";
      user = {
        name = "johnnie";
        homeDirectory = "/Users/johnnie";
      };
      home = {
        stateVersion = "26.05";
        module =
          let
            inherit (inputs.dotfiles-private) workProfile;
          in
          {
            imports = [ workstationHomeModule ];

            vcs.identityPolicy = {
              identities.work = {
                name = "Johnnie Kearse III";
                inherit (workProfile) email;
              };
              repositoryScopes = [
                {
                  root = workProfile.repositoriesRoot;
                  identity = "work";
                }
              ];
            };
          };
      };
      darwin = {
        stateVersion = 5;
        module = workstationDarwinModule;
      };
    };
  };
}
