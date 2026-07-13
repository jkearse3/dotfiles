{
  internalPkgs,
  ...
}:
{
  home.packages = [
    internalPkgs.commit-message-check
    internalPkgs.commit-message-format
  ];
}
