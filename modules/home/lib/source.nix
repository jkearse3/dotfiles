{
  config,
  dotfilesSource,
  lib,
  ...
}:
{
  _module.args.mkSource = import ./mkSource.nix {
    inherit config dotfilesSource lib;
  };
}
