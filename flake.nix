{
  nixConfig = {
    extra-substituters = [
      "https://cache.numtide.com"
    ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager-unstable = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    flake-parts.url = "github:hercules-ci/flake-parts";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    dotfiles-private.url = "git+ssh://git@github.com/jkearse3/dotfiles-private";
  };

  outputs =
    inputs@{
      flake-parts,
      ...
    }:
    flake-parts.lib.mkFlake
      {
        inherit inputs;
      }
      {
        imports = [
          inputs.treefmt-nix.flakeModule

          # The output module defines the declaration interface consumed by the
          # authored blueprints; the Nix module system merges both imports.
          ./flake/blueprint-outputs.nix
          ./blueprints

          ./flake/devshell.nix
          ./flake/packages.nix
          ./flake/treefmt.nix
        ];

        systems = [
          "aarch64-darwin"
        ];
      };
}
