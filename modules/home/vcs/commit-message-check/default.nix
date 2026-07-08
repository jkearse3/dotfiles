{
  pkgs,
  self,
  ...
}:
{
  home.packages = [
    self.packages.${pkgs.system}.commit-message-check
  ];
}
