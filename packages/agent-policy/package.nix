{
  jujutsu,
  pkgs,
}:
let
  inherit (pkgs.python3Packages) python;
in
pkgs.python3Packages.buildPythonApplication {
  pname = "agent-policy";
  version = "0.0.0";
  pyproject = true;

  src = ./.;
  build-system = [ pkgs.python3Packages.setuptools ];

  # `agent-policy run` execs the real tool with the caller's environment, so
  # the executable must not be a wrapper that exports PATH or
  # PYTHONNOUSERSITE. This launcher instead isolates the interpreter (`-I`)
  # and imports the package from its absolute site-packages path.
  dontWrapPythonPrograms = true;
  postInstall = ''
    cat >"$out/bin/agent-policy" <<EOF
    #!${python.interpreter} -I
    import sys
    sys.path.insert(0, "$out/${python.sitePackages}")
    from agent_policy.cli import main
    sys.exit(main())
    EOF
  '';
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
