{
  inputs,
  withSystem,
}:
{
  blueprintId,
  os,
  username,
  system,
  extraSystemModules ? [ ],
  ...
}:
assert os == "darwin";
assert builtins.elem system [
  "aarch64-darwin"
  "x86_64-darwin"
];
let
  darwinLib = inputs.darwin;
  darwinStateVersion = 5;
in
{
  flake.darwinConfigurations.${blueprintId} = withSystem system (
    {
      unstablePkgs,
      ...
    }:
    darwinLib.lib.darwinSystem {
      inherit system;
      modules = [
        {
          nixpkgs.pkgs = unstablePkgs;

          system.primaryUser = username;
          system.stateVersion = darwinStateVersion;

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
      ]
      ++ extraSystemModules;
      specialArgs = {
        inherit inputs;
      };
    }
  );
}
