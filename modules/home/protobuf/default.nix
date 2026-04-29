{
  pkgs,
  ...
}:
{
  home.packages = [
    pkgs.buf # Also provides buf_ls and linter buf_lint.
    pkgs.protobuf
  ];
}
