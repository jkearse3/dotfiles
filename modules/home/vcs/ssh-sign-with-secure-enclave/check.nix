# Builds the signing program around a stand-in `ssh-keygen` and runs
# `test.sh` against it. The stand-in records its arguments, environment, and
# stdin in the directory the test names in SIGNER_TEST_RECORD.
{
  bash,
  callPackage,
  lib,
  runCommand,
  writeShellScript,
}:
let
  standIn = writeShellScript "ssh-keygen-stand-in" ''
    record=$SIGNER_TEST_RECORD
    echo "$*" >"$record/args"
    cat >"$record/stdin"
    {
      echo "SSH_AUTH_SOCK=''${SSH_AUTH_SOCK-<unset>}"
      echo "SSH_ASKPASS=''${SSH_ASKPASS-<unset>}"
      echo "SSH_ASKPASS_REQUIRE=''${SSH_ASKPASS_REQUIRE-<unset>}"
      echo "SSH_SK_PROVIDER=''${SSH_SK_PROVIDER-<unset>}"
    } >"$record/env"
    echo "stand-in notice" >&2
    if [ -e "$record/fail" ]; then exit 3; fi
    echo SIGNATURE
  '';
  signer = callPackage ./package.nix { sshKeygen = standIn; };
in
runCommand "ssh-sign-with-secure-enclave-check" { } ''
  ${lib.getExe bash} ${./test.sh} ${lib.getExe signer}
  touch "$out"
''
