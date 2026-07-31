{
  dotfilesPackages,
  ...
}:
{
  home.packages = [
    dotfilesPackages.commit-message
  ];
}
