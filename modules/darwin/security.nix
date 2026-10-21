_: {
  security.pam.services.sudo_local.touchIdAuth = true;

  # Distrust roots exposed by the eMudhra intermediate key compromise
  # (Mozilla bug 2083449, CVE-2026-111943), mirroring the NixOS stopgap in
  # nixpkgs PR #576390. The emSign entries become redundant once the locked
  # nixpkgs ships cacert 3.131.1 (nixpkgs PR #576347); "Comodo AAA Services
  # root" stays blacklisted.
  security.pki.caCertificateBlacklist = [
    "Comodo AAA Services root"
    "emSign ECC Root CA - G3"
    "emSign Root CA - C1"
    "emSign ECC Root CA - C3"
  ];
}
