# The `migrate-jj-signing-key` command the jj signing-key activation step
# runs, built only after its fixture test passes against it.
{
  lib,
  python3,
  runCommandLocal,
  writeShellApplication,
}:
let
  migrate = writeShellApplication {
    name = "migrate-jj-signing-key";
    text = ''
      exec ${lib.getExe python3} -I ${./migrate.py} "$@"
    '';
  };
in
runCommandLocal "migrate-jj-signing-key-checked" { meta.mainProgram = "migrate-jj-signing-key"; } ''
  bash ${./migrate-test.sh} ${lib.getExe migrate}
  ln -s ${migrate} "$out"
''
