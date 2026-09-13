{
  neovim,
  pkgs,
}:
pkgs.stdenvNoCC.mkDerivation {
  pname = "nvim-pack";
  version = "0-unstable";

  src = ./.;

  nativeBuildInputs = [
    pkgs.installShellFiles
    pkgs.makeWrapper
    pkgs.python3
  ];
  nativeInstallCheckInputs = [
    pkgs.fish
    pkgs.git
    neovim
    pkgs.zsh
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 nvim_pack.py "$out/bin/nvim-pack"
    install -Dm644 nvim_pack.lua "$out/libexec/nvim-pack/nvim_pack.lua"
    patchShebangs "$out/bin/nvim-pack"
    wrapProgram "$out/bin/nvim-pack" \
      --set NVIM_PACK_SCRIPT "$out/libexec/nvim-pack/nvim_pack.lua" \
      --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.fzf ]}
    installShellCompletion --cmd nvim-pack \
      --fish nvim-pack.fish \
      --zsh _nvim-pack
    # The host's nvim supplies both the active plugin set and the lockfile path.
    # Only fzf is added to PATH; nvim remains inherited from the calling shell.

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    python3 -B nvim_pack_test.py
    NVIM_PACK_PROGRAM="$out/bin/nvim-pack" python3 -B nvim_pack_integration_test.py
    fish -n nvim-pack.fish
    zsh -n _nvim-pack
    "$out/bin/nvim-pack" --help >/dev/null
    "$out/bin/nvim-pack" list --help >/dev/null
    "$out/bin/nvim-pack" check --help >/dev/null
    "$out/bin/nvim-pack" update --help >/dev/null
    "$out/bin/nvim-pack" prune --help >/dev/null

    runHook postInstallCheck
  '';
}
