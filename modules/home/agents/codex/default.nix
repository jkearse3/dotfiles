{
  agentInteractivePolicy,
  dotfilesPackages,
  lib,
  mkSource,
  pkgs,
  ...
}:
let
  codexDefaults = builtins.fromTOML (builtins.readFile ./config.toml);
  preventIdleSleep = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin "/usr/bin/caffeinate -i ";

  codex = pkgs.writeShellApplication {
    name = "codex";
    text = ''
      ${agentInteractivePolicy.shellExports}
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
        assertion = codexDefaults.check_for_update_on_startup == false;
        message = "Codex must leave updates to the pinned Nix package";
      }
      {
        assertion = codexDefaults.cli_auth_credentials_store == "keyring";
        message = "Codex credentials must stay in the OS keyring";
      }
      {
        assertion = !(codexDefaults ? projects);
        message = "Codex project trust must stay in the machine-local profile";
      }
    ];

    home.packages = [ codex ];

    home.file = {
      # Codex layers the writable, machine-local dotfiles profile over these
      # tracked defaults. Trusted project config and explicit CLI overrides
      # still take precedence over the profile.
      ".codex/config.toml".source = ./config.toml;
      ".codex/rules/dotfiles.rules".source = mkSource ./dotfiles.rules;
      ".config/fish/completions/codex.fish".source = codexFishCompletion;
    };
  };
}
