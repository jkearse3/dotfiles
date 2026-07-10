{
  perSystem = _: {
    treefmt = {
      projectRootFile = "flake.nix";
      programs = {
        nixfmt.enable = true;
        stylua.enable = true;
        shfmt = {
          enable = true;
          indent_size = 0;
        };
        taplo.enable = true;
        prettier.enable = true;
      };
    };
  };
}
