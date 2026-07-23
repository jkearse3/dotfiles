{
  jj-ensure,
  jujutsu,
  pkgs,
}:
pkgs.python3Packages.buildPythonApplication {
  pname = "jj-worktree-add";
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
    jj-ensure
    jujutsu
    pkgs.zsh
  ];

  postInstall = ''
    installShellCompletion --cmd jj-worktree-add \
      --fish jj-worktree-add.fish \
      --zsh _jj-worktree-add
  '';

  postFixup = ''
    wrapProgram "$out/bin/jj-worktree-add" \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.git
          jj-ensure
          jujutsu
        ]
      }
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    python3 -B -m unittest discover -s tests -p 'test_*.py'
    python3 -B -m unittest discover -s tests -p 'completion_test.py'
    "$out/bin/jj-worktree-add" --help >/dev/null
    runHook postInstallCheck
  '';
}
