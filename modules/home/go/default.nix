{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages = [
    pkgs.delve
    pkgs.go
    pkgs.gofumpt
    pkgs.golangci-lint
    pkgs.gopls
    (
      # Avoid bin/modernize conflict with gopls; lowPrio lets gopls take precedence.
      lib.meta.lowPrio pkgs.gotools
    )
  ];
  home.sessionVariables = {
    GOPRIVATE = "github.com/jkearse3";
  };
  home.sessionPath = [
    "${config.home.homeDirectory}/go/bin"
  ];
}
