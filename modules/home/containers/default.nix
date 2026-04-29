{
  pkgs,
  ...
}:
{
  home.packages = [
    pkgs.dive
    pkgs.k9s
    pkgs.kind
    pkgs.kubectl
    pkgs.kubectx
    pkgs.lazydocker
  ];
}
