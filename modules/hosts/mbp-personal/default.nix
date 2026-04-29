{
  inputs,
  withSystem,
  ...
}:
let
  args = {
    hostname = "mbp-personal";
    username = "johnnie";
    system = "aarch64-darwin";
  };
in
{
  imports = [
    ((import ../mkDarwin.nix { inherit inputs withSystem; }) args)
    ((import ../mkHome.nix { inherit inputs withSystem; }) args)
  ];
}
