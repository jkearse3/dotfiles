{
  config,
  pkgs,
  ...
}:
{
  home = {
    packages = [
      # The rust-overlay provides toolchain management instead of rustup.
      (pkgs.rust-bin.stable.latest.default.override {
        extensions = [
          "rust-src" # Required by rust-analyzer.
          "rust-analyzer"
          "clippy"
          "rustfmt"
        ];
      })
    ];
    sessionPath = [
      "${config.home.homeDirectory}/.cargo/bin"
    ];
    file.".cargo/config.toml".text = # toml
      ''
        [net]
        git-fetch-with-cli = true
      '';
  };
}
