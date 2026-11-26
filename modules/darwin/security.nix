_: {
  # sudo asks for the password in the terminal rather than through Touch ID.
  # Rex and herdr start their panes from the desktop session, so pam_tid treats
  # a sudo there as local and puts its dialog on this Mac's screen, where no one
  # can answer it while the user works in those panes from another machine or a
  # phone. pam_tid offers no way to skip it for one session but not another.
  security.pam.services.sudo_local.touchIdAuth = false;

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
