{
  dotfilesPackages,
  lib,
  mkSource,
  pkgs,
  ...
}:
let
  # Keep Neovim socket paths below macOS's limit when direnv lengthens TMPDIR.
  darwinRuntimeDirectoryWrapperArgs = lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
    "--run"
    ''
      if [ -z "''${XDG_RUNTIME_DIR:-}" ]; then
        darwin_runtime_directory="$(/usr/bin/getconf DARWIN_USER_TEMP_DIR || true)"
        if [ -n "$darwin_runtime_directory" ]; then
          export XDG_RUNTIME_DIR="''${darwin_runtime_directory%/}"
        fi
      fi
    ''
  ];
in
{
  imports = [ ../lib/source.nix ];

  programs.neovim = {
    enable = true;
    extraWrapperArgs = darwinRuntimeDirectoryWrapperArgs;
    sideloadInitLua = true;
    withNodeJs = false;
    withPerl = false;
    withPython3 = false;
    withRuby = false;
  };

  home = {
    packages = [
      pkgs.copilot-language-server
      pkgs.tree-sitter
      dotfilesPackages.nvim-pack-prune
    ];
    sessionVariables = {
      EDITOR = "nvim";
    };
    file.".config/nvim".source = mkSource ./nvim;
  };
}
