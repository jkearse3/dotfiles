{
  inputs,
  withSystem,
  ...
}:
let
  args = {
    hostname = "jk3-lap-001";
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
