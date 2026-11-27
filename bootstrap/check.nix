# Runs `tests/git-key-test.sh` against `git_key.py` with stand-ins for
# `sc_auth` and `ssh-keygen`, so it never touches the Secure Enclave or the
# user's `~/.ssh`. The test runs the script with the python3 that
# `git-key.sh` runs, the one from the nixpkgs that flake.lock pins. The
# stand-ins and the test use macOS's own perl, ssh-keygen, stat, and pgrep,
# which a Darwin build reaches only with the sandbox off, as on this flake's
# Macs. `handleRelative` is where the script must install the handle,
# relative to the home directory.
{
  bash,
  lib,
  python3,
  runCommand,
  handleRelative,
}:
runCommand "git-key-bootstrap" { meta.platforms = lib.platforms.darwin; } ''
  ${lib.getExe bash} ${./tests/git-key-test.sh} ${lib.getExe python3} ${./git_key.py} ${./tests/stubs} ${./tests/fixtures} ${lib.escapeShellArg handleRelative}
  touch "$out"
''
