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
      "chatgpt"
      "claude"
      "docker-desktop"
      "firefox"
      "font-jetbrains-mono-nerd-font"
      "ghostty"
      "google-chrome"
      "notion"
      "slack"
      "spotify"
      "stats"
      "tailscale-app"
      "zed"
    ];
  };
}
