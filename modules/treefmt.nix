{
  perSystem =
    {
      ...
    }:
    {
      treefmt = {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
        programs.stylua.enable = true;
        programs.shfmt = {
          enable = true;
          indent_size = 0;
        };
        programs.taplo.enable = true;
        programs.prettier.enable = true;
      };
    };
}
