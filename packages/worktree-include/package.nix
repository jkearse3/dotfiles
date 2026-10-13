{
  git,
  pkgs,
}:
pkgs.stdenvNoCC.mkDerivation {
  pname = "worktree-include";
  version = "0.0.0";

  src = ./.;

  nativeBuildInputs = [
    pkgs.makeWrapper
    pkgs.python3Minimal
  ];
  nativeInstallCheckInputs = [
    git
    pkgs.python3Minimal
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 worktree-include.py "$out/bin/worktree-include"
    patchShebangs "$out/bin/worktree-include"
    wrapProgram "$out/bin/worktree-include" \
      --set WORKTREE_INCLUDE_GIT "${git}/bin/git"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    WORKTREE_INCLUDE_PROGRAM="$out/bin/worktree-include" \
      python3 -B -m unittest discover -s tests -p 'test_*.py'
    "$out/bin/worktree-include" --help > /dev/null
    runHook postInstallCheck
  '';
}
