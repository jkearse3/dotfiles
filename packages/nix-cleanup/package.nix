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
    # `nix` is deliberately not pinned here: it must match the host's running
    # daemon, so the tool resolves it from PATH. `lsof` is pinned because the
    # script parses its output format and macOS ships a different build.
    wrapProgram "$out/bin/nix-cleanup" \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.lsof
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
