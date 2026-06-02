# Nono

Rules for authoring repo-local `nono` profile overlays for wrapped coding agents.

## Runtime Detection

- Treat `NONO_CAP_FILE` as the signal that the current process is running inside `nono`.
- If `NONO_CAP_FILE` is absent, do not assume `nono` is active just because the `nono` binary
  exists.

## Repo Overlays

- Use `.nono/profile.json` for this dotfiles setup's supported repo-local overlay.
- Run `nono profile guide` before authoring or materially changing a `nono` profile.
- Normally extend the shared coding-agent profile:

```json
{
  "extends": "coding-agents"
}
```

- Keep overlay additions narrow and repo-specific.
- Prefer `$WORKDIR` and `$HOME` variables over user-specific absolute paths.
- Keep standalone global profile authoring out of scope unless the user explicitly asks for it. If
  needed, use `nono profile guide` as the live schema source of truth.

## Validation And Debugging

- Validate repo overlays with `nono profile validate .nono/profile.json`.
- After changing `.nono/profile.json`, tell the user to restart the wrapped agent/sandbox. The
  current agent is running inside the old sandbox and keeps the profile policy it started with.
- Inspect the effective profile with `nono profile show .nono/profile.json`.
- Compare profile behavior with `nono profile diff coding-agents .nono/profile.json` when debugging
  unexpected permissions.

## Pitfalls

- `filesystem.bypass_protection` only bypasses nono protection checks. It does not grant filesystem
  access.
- `filesystem.suppress_save_prompt` only suppresses prompts. It does not grant filesystem access.
- `commands.*` config applies at startup. It does not grant command execution permission after the
  sandbox is running.
