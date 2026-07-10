{ pkgs }:

let
  package = pkgs.buildNpmPackage {
    pname = "playwright-cli";
    version = "0.1.17";

    src = pkgs.fetchFromGitHub {
      owner = "microsoft";
      repo = "playwright-cli";
      rev = "793cfb32572733cbcb401e6f28d05a7a914ce408";
      hash = "sha256-tc/2Qck3mm6BqWTu2lvvfsM0/BHO/Z0ZvCdFZ7QQqKI=";
    };

    npmDepsHash = "sha256-u44jWprmr3RdzB3aDL3K0ShT5lLxr175z3C8pN43YFA=";
    dontNpmBuild = true;

    meta = {
      description = "Agent-oriented Playwright CLI";
      homepage = "https://github.com/microsoft/playwright-cli";
      license = pkgs.lib.licenses.asl20;
      mainProgram = "playwright-cli";
    };
  };
in
pkgs.symlinkJoin {
  name = "playwright-cli-${package.version}";
  inherit (package) version;
  paths = [ package ];
  buildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/playwright-cli \
      --set PLAYWRIGHT_BROWSERS_PATH ${pkgs.playwright-driver.browsers} \
      --set PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS true \
      --run 'export PLAYWRIGHT_DAEMON_SOCKETS_DIR="/tmp/playwright-cli-''${USER:-user}"'
  '';
  inherit (package) meta;
  passthru.updateScript = ./update.sh;
}
