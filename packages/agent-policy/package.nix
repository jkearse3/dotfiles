{
  jujutsu,
  pkgs,
}:
pkgs.python3Packages.buildPythonApplication {
  pname = "agent-policy";
  version = "0.0.0";
  pyproject = true;

  src = ./.;
  build-system = [ pkgs.python3Packages.setuptools ];
  # The jj-push-dry-run tests run real jj against a local bare git remote.
  nativeCheckInputs = [
    jujutsu
    pkgs.git
  ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    AGENT_POLICY="$out/bin/agent-policy" \
      python3 -B -m unittest discover -s tests -p 'test_*.py'
    "$out/bin/agent-policy" --help >/dev/null
    "$out/bin/agent-policy" run --help >/dev/null
    "$out/bin/agent-policy" validate --help >/dev/null
    runHook postInstallCheck
  '';
}
