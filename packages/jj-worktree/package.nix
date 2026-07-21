{
  jujutsu,
  pkgs,
}:
pkgs.python3Packages.buildPythonApplication {
  pname = "jj-worktree";
  version = "0.0.0";
  pyproject = true;

  src = ./.;

  build-system = [
    pkgs.python3Packages.setuptools
  ];

  nativeBuildInputs = [
    pkgs.installShellFiles
    pkgs.makeWrapper
  ];

  nativeCheckInputs = [
    pkgs.fish
    pkgs.git
    jujutsu
    pkgs.nix
    pkgs.zsh
  ];

  postInstall = ''
    installShellCompletion --cmd jj-worktree \
      --fish jj-worktree.fish \
      --zsh _jj-worktree
  '';

  postFixup = ''
    wrapProgram "$out/bin/jj-worktree" \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.git
          jujutsu
        ]
      }
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    python3 -B -m unittest discover -s tests -p 'test_*.py'
    PATH="$out/bin:$PATH" JJ_WORKTREE_EXECUTABLE="$out/bin/jj-worktree" \
      python3 -B -m unittest discover -s tests -p 'completion_test.py'
    "$out/bin/jj-worktree" --help >/dev/null

    runHook postInstallCheck
  '';
}
