{
  pkgs,
  ...
}:
{
  home.packages = [
    pkgs.go-jsonnet # Also provides jsonnetfmt.
    pkgs.jsonnet-language-server
  ];
}
