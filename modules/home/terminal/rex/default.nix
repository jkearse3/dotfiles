_: {
  # Rex reads its keybindings from this file. Rex itself is installed as a
  # macOS app outside Nix, so this module only manages the config.
  home.file.".config/rex/init.lua".source = ./init.lua;
}
