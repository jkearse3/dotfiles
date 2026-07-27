---
name: nono
description:
  Use when working with nono sandbox detection, repo-local `.nono/profile.json`
  overlays, or nono profile validation.
---

# Nono

Rules for `nono` sandbox detection and repo-local profile overlays.

## Runtime

- Treat `NONO_CAP_FILE` as the signal that the current process is running inside
  `nono`.
- If `NONO_CAP_FILE` is absent, do not assume `nono` is active.

## Profiles

- Use `.nono/profile.json` for this dotfiles setup's supported repo-local
  overlay.
- Keep overlay additions narrow and repo-specific.
- Prefer `$WORKDIR` and `$HOME` over user-specific absolute paths.
- Normally extend the shared coding-agent profile:

```json
{
  "extends": "coding-agents"
}
```

- Run `nono profile guide` before materially changing a profile.
- Validate repo overlays with `nono profile validate .nono/profile.json`.
- After changing `.nono/profile.json`, tell the user to restart the wrapped
  agent/sandbox.

## Pitfalls

- `filesystem.bypass_protection` and `filesystem.suppress_save_prompt` do not
  grant filesystem access.
- `commands.*` config applies at startup. It does not grant command execution
  permission later.
