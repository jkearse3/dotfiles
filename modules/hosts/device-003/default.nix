{
  inputs,
  withSystem,
  ...
}:
let
  args = {
    hostname = "device-003";
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
