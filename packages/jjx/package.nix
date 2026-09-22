{
  commit-message,
  jujutsu,
  pkgs,
}:
let
  runtimePath = pkgs.lib.makeBinPath [
    pkgs.fzf
    pkgs.git
    commit-message
    jujutsu
  ];
in
pkgs.python3Packages.buildPythonApplication {
  pname = "jjx";
  version = "0.0.0";
  pyproject = true;

  src = ./.;
  build-system = [ pkgs.python3Packages.setuptools ];
  nativeBuildInputs = [
    pkgs.installShellFiles
    pkgs.makeWrapper
  ];
  nativeCheckInputs = [
    commit-message
    jujutsu
    pkgs.fish
    pkgs.fzf
    pkgs.git
    pkgs.zsh
  ];

  postInstall = ''
    installShellCompletion --cmd jjx \
      --fish completions/jjx.fish \
      --zsh completions/_jjx
  '';

  postFixup = ''
    wrapProgram "$out/bin/jjx" --prefix PATH : "${runtimePath}"
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export PATH="$out/bin:$PATH"

    python3 -B -m unittest discover -s tests -t . -p 'test_*.py'
    python3 -B -m unittest discover -s tests/jjx -t . -p 'completion_test.py'
    fish -n completions/jjx.fish
    zsh -n completions/_jjx
    "$out/bin/jjx" --help >/dev/null
    for group in bookmark change description worktree; do
      "$out/bin/jjx" "$group" --help >/dev/null
    done

    runHook postInstallCheck
  '';
}
