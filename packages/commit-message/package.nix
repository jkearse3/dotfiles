{
  pkgs,
}:
pkgs.python3Packages.buildPythonApplication {
  pname = "commit-message";
  version = "0.0.0";
  pyproject = true;

  src = ./.;
  build-system = [ pkgs.python3Packages.setuptools ];

  nativeBuildInputs = [ pkgs.installShellFiles ];

  nativeCheckInputs = [
    pkgs.fish
    pkgs.zsh
  ];

  postInstall = ''
    installShellCompletion --cmd commit-message \
      --fish commit-message.fish \
      --zsh _commit-message
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    COMMIT_MESSAGE="$out/bin/commit-message" \
      python3 -B -m unittest discover -s tests -p 'test_*.py'
    python3 -B -m unittest discover -s tests -p 'completion_test.py'
    "$out/bin/commit-message" format --help >/dev/null
    "$out/bin/commit-message" validate --help >/dev/null
    runHook postInstallCheck
  '';
}
