{
  pkgs,
}:
pkgs.stdenvNoCC.mkDerivation {
  pname = "nvim-pack-prune";
  version = "0-unstable";

  src = ./.;

  nativeBuildInputs = [
    pkgs.python3
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 nvim_pack_prune.py "$out/bin/nvim-pack-prune"
    patchShebangs "$out/bin/nvim-pack-prune"
    # `nvim` is deliberately not pinned and not wrapped onto PATH: the tool must
    # source this host's own init.lua so the vim.pack `active` set reflects the
    # machine's real config, matching nix-cleanup's unpinned-`nix` rationale.

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    python3 -B nvim_pack_prune_test.py
    "$out/bin/nvim-pack-prune" --help >/dev/null

    runHook postInstallCheck
  '';
}
