# Nix (Determinate)

- Base conf: `/etc/nix/nix.conf`
- User conf: `/etc/nix/nix.custom.conf` (determinate-specific: `eval-cores`,
  `lazy-trees`)
- Restart daemon (macOS):
  `sudo launchctl kickstart -k system/systems.determinate.nix-daemon`
- Git cache corruption: `~/.cache/nix` can corrupt, causing `object not found`
  errors during eval/build. Fix: `rm -rf ~/.cache/nix`.

## Disk cleanup

`nh clean` deletes old profile generations and some GC roots, then runs
`nix store gc`. Home Manager installs `nh` from the same nixpkgs as the flake
apps.

```sh
nh clean user --dry --keep-one                  # preview, no sudo
nh clean all --ask --keep-one                   # show the plan, confirm, delete
nh clean all --ask --keep-one --keep-since 30d  # keep the last 30 days
```

- `user` covers `~/.local/state/nix/profiles` (`profile`, `home-manager`,
  `channels`) and needs no sudo. nh reads that path directly, not
  `$XDG_STATE_HOME`.
- `all` re-runs itself through sudo before doing anything, even with `--dry`. It
  adds every profile in `/nix/var/nix/profiles`, including the nix-darwin
  `system` profile and Determinate's `default` profile, and the
  `~/.local/state/nix/profiles` of root and of users with UIDs 501-600.
- Without `--delete-current`, the current generation is kept. `--keep N` keeps
  at least N generations (default 1); `--keep-since` also keeps everything newer
  than the given age.
- GC roots: nh deletes roots whose target is gone. Of live roots, it deletes
  only those of `result`/`result-*` links and direnv dev shells older than
  `--keep-since` (default `0h`, so all of them); other roots, such as
  `current-home` or a custom `--out-link`, stay. It deletes the root entry in
  `/nix/var/nix/gcroots/auto`, not the link, which dangles once GC collects its
  target. Only root can write there, so `user` lists roots it then fails to
  delete. `--keep-one` keeps every direnv root whose `.direnv` link still
  exists, so dev shells are not rebuilt; `--no-gcroots` leaves all GC roots
  alone.

`nix store gc` alone deletes unreachable store paths, never generations.
