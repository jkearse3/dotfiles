# The `migrate-jj-sign-on-push` command the jj sign-on-push activation step
# runs, built only after its fixture test passes against it.
{
  lib,
  python3,
  runCommandLocal,
  writeShellApplication,
}:
let
  migrate = writeShellApplication {
    name = "migrate-jj-sign-on-push";
    text = ''
      exec ${lib.getExe python3} -I ${./migrate.py} "$@"
    '';
  };
in
runCommandLocal "migrate-jj-sign-on-push-checked" { meta.mainProgram = "migrate-jj-sign-on-push"; }
  ''
    bash ${./migrate-test.sh} ${lib.getExe migrate}
    ln -s ${migrate} "$out"
  ''
