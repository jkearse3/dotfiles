{
  git,
  pkgs,
}:
pkgs.stdenvNoCC.mkDerivation {
  pname = "direnv-worktree";
  version = "0.0.0";

  src = ./.;

  nativeBuildInputs = [
    pkgs.installShellFiles
    pkgs.makeWrapper
    pkgs.python3Minimal
  ];
  nativeInstallCheckInputs = [
    pkgs.fish
    git
    pkgs.python3Minimal
    pkgs.zsh
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 direnv-worktree.py "$out/bin/direnv-worktree"
    patchShebangs "$out/bin/direnv-worktree"
    wrapProgram "$out/bin/direnv-worktree" \
      --set DIRENV_WORKTREE_DIRENV "${pkgs.direnv}/bin/direnv" \
      --set DIRENV_WORKTREE_GIT "${git}/bin/git" \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.coreutils
          pkgs.direnv
          git
          pkgs.python3Minimal
        ]
      }
    installShellCompletion --cmd direnv-worktree \
      --fish direnv-worktree.fish \
      --zsh _direnv-worktree
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    DIRENV_WORKTREE_BIN="$out/bin" \
      DIRENV_WORKTREE_PROGRAM="$out/bin/.direnv-worktree-wrapped" \
      python3 -B -m unittest discover -s tests -p 'test_*.py'
    python3 -B -m unittest discover -s tests -p 'completion_test.py'
    runHook postInstallCheck
  '';
}
