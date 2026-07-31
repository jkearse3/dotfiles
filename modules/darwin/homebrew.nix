_: {
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
