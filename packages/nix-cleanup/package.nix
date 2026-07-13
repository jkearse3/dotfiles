{
  pkgs,
}:
pkgs.stdenvNoCC.mkDerivation {
  pname = "nix-cleanup";
  version = "0-unstable";

  src = ./.;

  nativeBuildInputs = [
    pkgs.makeWrapper
    pkgs.python3
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 nix_cleanup.py "$out/bin/nix-cleanup"
    patchShebangs "$out/bin/nix-cleanup"
    wrapProgram "$out/bin/nix-cleanup" \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.lsof
          pkgs.nix
        ]
      }

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    python3 -B nix_cleanup_test.py
    "$out/bin/nix-cleanup" --help >/dev/null

    runHook postInstallCheck
  '';
}
