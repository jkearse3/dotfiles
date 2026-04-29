{
  inputs,
  withSystem,
  ...
}:
let
  args = {
    hostname = "mbp-hf-2";
    username = "johnnie";
    system = "aarch64-darwin";
  };
  homeArgs = args // {
    extraHomeModules = [
      inputs.dotfiles-private.homeModules.hf
    ];
  };
in
{
  imports = [
    ((import ../mkDarwin.nix { inherit inputs withSystem; }) args)
    ((import ../mkHome.nix { inherit inputs withSystem; }) homeArgs)
  ];
}
