{
  pkgs,
  ...
}:
{
  # Project environments can shadow these global defaults with pinned clients.
  home.packages = [
    pkgs.mariadb.client
    pkgs.postgresql
    pkgs.sqlite
  ];
}
