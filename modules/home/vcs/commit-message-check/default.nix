{
  internalPkgs,
  ...
}:
{
  home.packages = [
    internalPkgs.commit-message-check
  ];
}
