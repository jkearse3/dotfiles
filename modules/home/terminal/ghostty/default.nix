{
  pkgs,
  lib,
  ...
}:
{
  programs.ghostty = {
    enable = true;
    package = null;
    settings = {
      font-feature = [
        "-calt"
        "-liga"
        "-dlig"
      ];
      window-height = 55;
      window-width = 190;
      command = "${lib.getExe pkgs.fish} --login --interactive";
      theme = "tokyonight";
      keybind = [
        "shift+enter=text:\\n"
      ];
    };
  };
}
