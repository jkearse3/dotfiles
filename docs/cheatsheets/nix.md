# Nix (Determinate)

- Base conf: `/etc/nix/nix.conf`
- User conf: `/etc/nix/nix.custom.conf` (determinate-specific: `eval-cores`, `lazy-trees`)
- Restart daemon (macOS): `sudo launchctl kickstart -k system/systems.determinate.nix-daemon`
- Git cache corruption: `~/.cache/nix` can corrupt, causing `object not found` errors during
  eval/build. Fix: `rm -rf ~/.cache/nix`.
