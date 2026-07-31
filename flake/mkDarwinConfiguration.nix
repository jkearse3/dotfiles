{
  inputs,
  withSystem,
}:
blueprint:
withSystem blueprint.system (
  {
    unstablePkgs,
    ...
  }:
  inputs.darwin.lib.darwinSystem {
    inherit (blueprint) system;
    modules = [
      {
        nixpkgs.pkgs = unstablePkgs;

        system.primaryUser = blueprint.user.name;
        system.stateVersion = blueprint.darwin.stateVersion;

        # Determinate Nix manages the daemon; disable nix-darwin daemon management.
        nix.enable = false;

        security.pam.services.sudo_local.touchIdAuth = true;

        programs.fish.enable = true;

        homebrew = {
          enable = true;
          onActivation = {
            autoUpdate = false;
            upgrade = false;
            cleanup = "none";
          };
          casks = [
            "1password"
            "docker-desktop"
            "font-jetbrains-mono-nerd-font"
            "ghostty"
            "google-chrome"
            "tailscale-app"
            "yubico-yubikey-manager"
          ];
        };
      }
      blueprint.darwin.module
    ];
  }
)
