# The `rex-agents` command. It calls `rex`, which Rex installs outside Nix, so
# the Rex home module (`modules/home/terminal/rex`) puts its `rex` wrapper on
# this command's PATH; the build's tests use a fake Rex instead.
{ pkgs }:
pkgs.python3Packages.buildPythonApplication {
  pname = "rex-agents";
  version = "0.0.0";
  pyproject = true;

  src = ./.;
  build-system = [ pkgs.python3Packages.setuptools ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    python3 -B -m unittest discover -s tests -t . -p 'test_*.py'
    "$out/bin/rex-agents" --help >/dev/null
    for command in start watch resume release ls; do
      "$out/bin/rex-agents" "$command" --help >/dev/null
    done

    runHook postInstallCheck
  '';
}
