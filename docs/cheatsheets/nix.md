# Nix (Determinate)

- Base conf: `/etc/nix/nix.conf`
- User conf: `/etc/nix/nix.custom.conf` (determinate-specific: `eval-cores`,
  `lazy-trees`)
- Restart daemon (macOS):
  `sudo launchctl kickstart -k system/systems.determinate.nix-daemon`
- Git cache corruption: `~/.cache/nix` can corrupt, causing `object not found`
  errors during eval/build. Fix: `rm -rf ~/.cache/nix`.

## Disk cleanup

`nix-cleanup` reports `/nix` usage, XDG user and Home Manager generation counts,
the nix-darwin system profile when present, direnv GC roots, and Nix store paths
held open by visible processes. Running it without a subcommand only prints
help.

```sh
nix-cleanup report
nix-cleanup preview
nix-cleanup preview --older-than 30
nix-cleanup clean --older-than 30
nix-cleanup clean
```

`preview` and `clean` operate only on
`$NIX_STATE_HOME/profiles/{profile,home-manager}`. Nix defaults that state
directory to `$XDG_STATE_HOME/nix`, then `~/.local/state/nix`. `clean` first
repeats the preview, uses `nix profile wipe-history` to remove only non-current
generations, and then runs `nix store gc`. Omit `--older-than` to remove all
non-current history. The current generation is always preserved by Nix.

nix-darwin system generations use a root-owned legacy profile and are separate:

```sh
nix-cleanup system-preview --older-than 30
nix-cleanup system-clean --older-than 30
```

Only `system-clean` uses `sudo`, and only for `nix-env --delete-generations`. On
hosts without `/nix/var/nix/profiles/system`, these commands report that the
profile is absent and do nothing.

The related Nix commands have different scopes:

- `nix store gc` deletes unreachable store paths but does not delete profile
  history.
- `nix-collect-garbage -d` deletes old generations in profiles that it
  discovers, then collects the store. It may not discover XDG-managed profiles
  such as the two above.
- `nix profile wipe-history --profile PATH` explicitly removes non-current
  generations from one selected profile. `--dry-run` previews and
  `--older-than Nd` retains newer generations.

A store GC dry-run reflects roots that exist at that moment, so it cannot
estimate the combined space that would be reclaimed after separately previewed
profile roots are removed. Nix store GC and root inspection may also prune stale
auto-GC-root symlinks even in dry-run or apparently read-only operations. The
command therefore counts root symlinks directly for reports and warns before
invoking `nix store gc --dry-run`.
