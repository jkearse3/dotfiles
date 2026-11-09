_: {
  security.pam.services.sudo_local.touchIdAuth = true;

  # Leaving services.openssh.enable unset keeps Remote Login under System
  # Settings' control; nix-darwin writes extraConfig to
  # /etc/ssh/sshd_config.d/100-nix-darwin.conf either way. The settings apply to
  # every account because a `Match User` rule compares the name the client
  # sends case-sensitively, which misses other spellings macOS resolves to the
  # same account.
  services.openssh.extraConfig = ''
    AuthenticationMethods publickey
    PasswordAuthentication no
    KbdInteractiveAuthentication no
  '';
}
