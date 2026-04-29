{
  pkgs,
  ...
}:
{
  home.packages = [
    pkgs.openssl
    pkgs.pkg-config
  ];
}
