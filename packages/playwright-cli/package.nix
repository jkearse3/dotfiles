{ pkgs }:

let
  package = pkgs.buildNpmPackage {
    pname = "playwright-cli";
    version = "0.1.22";

    src = pkgs.fetchFromGitHub {
      owner = "microsoft";
      repo = "playwright-cli";
      rev = "b85c7a736bb473bf55b584e54a09ffa698d6d871";
      hash = "sha256-80xzHvf7BHGvoKvMdkGeNUsUrpZrpw5eryuQM8NKT/E=";
    };

    npmDepsHash = "sha256-mGD7a/v1cx/xPGZo8nN3WA40mYGgF/KzMKiGbvUeX4E=";
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
