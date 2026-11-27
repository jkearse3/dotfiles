# The signing program git and jj run for SSH signatures. It runs `ssh-keygen`
# with Apple's Secure Enclave provider, so a signing key that is a Secure
# Enclave key handle signs, and without the 1Password agent or an askpass
# helper, so signing never contacts 1Password or waits on a prompt. jj sends
# the data on stdin and stores stdout as the signature, so both pass through.
{
  lib,
  openssh,
  writeShellApplication,
  sshKeygen ? lib.getExe' openssh "ssh-keygen",
}:
writeShellApplication {
  name = "ssh-sign-with-secure-enclave";
  text = ''
    unset SSH_AUTH_SOCK SSH_ASKPASS
    export SSH_ASKPASS_REQUIRE=never
    export SSH_SK_PROVIDER=/usr/lib/ssh-keychain.dylib
    exec ${sshKeygen} "$@"
  '';
}
