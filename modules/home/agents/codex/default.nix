{
  dotfilesPackages,
  lib,
  mkSource,
  pkgs,
  ...
}:
let
  codexProfile = builtins.fromTOML (builtins.readFile ./dotfiles.config.toml);
  preventIdleSleep = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin "/usr/bin/caffeinate -i ";

  codex = pkgs.writeShellApplication {
    name = "codex";
    text = ''
      exec ${preventIdleSleep}${lib.getExe dotfilesPackages.codex} --profile dotfiles "$@"
    '';
  };

  codexFishCompletion = pkgs.runCommandLocal "codex.fish" { } ''
    ${lib.getExe dotfilesPackages.codex} completion fish > "$out"
    test -s "$out"
  '';
in
{
  imports = [ ../../lib/source.nix ];

  config = {
    assertions = [
      {
        assertion = codexProfile.check_for_update_on_startup == false;
        message = "Codex must leave updates to the pinned Nix package";
      }
      {
        assertion = codexProfile.cli_auth_credentials_store == "keyring";
        message = "Codex credentials must stay in the OS keyring";
      }
    ];

    home.packages = [ codex ];

    home.file = {
      # The wrapper selects this tracked profile over Codex's unmanaged,
      # machine-local ~/.codex/config.toml. Trusted project config and explicit
      # CLI overrides still take precedence over the profile.
      ".codex/dotfiles.config.toml".source = mkSource ./dotfiles.config.toml;
      ".codex/rules/dotfiles.rules".source = mkSource ./dotfiles.rules;
      ".config/fish/completions/codex.fish".source = codexFishCompletion;
    };
  };
}
