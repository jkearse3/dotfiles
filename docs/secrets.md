# Secrets

Runtime secrets are delivered with [SecretSpec](https://secretspec.dev). The
committed `secretspec.toml` declares _what_ may be resolved; each machine
decides _which provider_ resolves it, mapped through a `dotfiles` provider
alias. No secret value or provider choice is ever committed.

- `secretspec.toml` (repository root) — value-free registry of secret contracts,
  grouped by consumer scope (e.g. `[scopes.opencode]`). One registry for the
  whole repository, not one per blueprint.
- `~/.config/secretspec/` (machine-local, never committed) — maps the `dotfiles`
  alias to a concrete provider and stores values there.
- `modules/home/secrets` — runs each consumer's command under `secretspec run`
  against a fixed store-path manifest, the `default` profile, and the consumer's
  scope. `SECRETSPEC_PROVIDER` overrides the alias for a single invocation.

The repository passes only secret names and provider selectors through Nix and
generated launchers; it does not resolve plaintext values during evaluation or
builds. SecretSpec injects values at runtime. This is not a guarantee about what
SecretSpec, a provider, or the launched application writes to logs, files, or
subprocess arguments. The wrappers require SecretSpec `>= 0.18.0` (asserted at
evaluation) from `nixpkgs-unstable`.

## Environment boundary

Each launcher pins its manifest, `default` profile, and scope rather than taking
those selectors from the caller's `SECRETSPEC_*` variables. Scoped execution
removes inherited manifest-declared names outside that scope, including names
from other profiles. An optional launcher's direct fallback when the alias is
absent applies the same filtering. In-scope ambient values and unrelated
environment variables survive; the scope is not a general environment allowlist.

SecretSpec resolves credentials before entering any consumer sandbox. The
consumer and its descendants can read admitted environment credentials; scope
filtering does not isolate secrets from child commands or restrict what those
commands can do with them.

## Commissioning a machine

Mapping the `dotfiles` alias is machine-local, not managed by Home Manager, and
repeated on every new machine. It affects only commands that request the alias,
not a machine-wide default. Until it is done, a secret-backed launcher fails
with guidance instead of running without secrets.

```sh
# In the dev shell (nix develop), which supplies secretspec.
# Provider by platform: macOS / desktop Linux → keyring://
#                       headless Linux        → pass:// or gopass://
secretspec config global provider add dotfiles keyring://
secretspec config global provider list
```

Then store each consumer's secret values — see [Consumers](#consumers).
Consumers whose secrets are all optional (like OpenCode) run without this step.

## Troubleshooting

- **"not commissioned for the dotfiles provider"** — the `dotfiles` alias is not
  registered. Run the `config global provider add` command above, or set
  `SECRETSPEC_PROVIDER` for a one-off. An unrelated alias does not satisfy this.
- **Provider configured but unavailable** (e.g. Linux `keyring` with no Secret
  Service) — SecretSpec fails rather than silently degrading. Repair the
  provider, choose another, or override for the invocation. The wrapper does not
  reinterpret a failing provider as an uncommissioned machine. Provider-list
  inspection errors also fail visibly. A nonempty `SECRETSPEC_PROVIDER` skips
  alias discovery, not scoped SecretSpec resolution; it never triggers an
  anonymous retry on failure.
- **Keychain prompts or access failures** — Keychain authorization and signing
  are separate from launcher scope filtering. This integration does not change
  Keychain access policy or remediate prompts.

## Backup and recovery

Values live in your chosen provider, so back them up its way (Keychain export,
`pass`'s git store). This repository keeps no recovery copy; if provider state
is lost, re-run commissioning and re-store each consumer's secrets.

## Consumers

Each consumer resolves one SecretSpec scope. The mechanism above is identical
for all of them; only the scope, its secrets, and their handling differ.

### OpenCode and Pi (`EXA_API_KEY`)

OpenCode and Pi resolve their respective `opencode` and `pi` scopes, whose only
secret is the optional `EXA_API_KEY` — an [Exa](https://exa.ai) search key.
Store, inspect, rotate, or remove it:

```sh
# Store or replace (hidden prompt; never on the command line).
secretspec set --file ~/dotfiles/secretspec.toml \
  --provider dotfiles --profile default EXA_API_KEY

# Check resolution without printing any value.
secretspec check --file ~/dotfiles/secretspec.toml \
  --provider dotfiles --profile default --scope opencode --explain
secretspec check --file ~/dotfiles/secretspec.toml \
  --provider dotfiles --profile default --scope pi --explain

# Remove it (free tier resumes).
secretspec delete --file ~/dotfiles/secretspec.toml \
  --provider dotfiles --profile default EXA_API_KEY
```

`EXA_API_KEY` is `required = false`, so it is not needed to commission a
machine. With no stored value, both clients still start on Exa's free tier:
`OPENCODE_ENABLE_EXA=1` remains unconditional, and Pi sends an empty `x-api-key`
header that Exa treats as anonymous access. The key raises quota; it does not
gate search. A stored provider value wins over an ambient `EXA_API_KEY`; with no
stored value, an ambient one survives into either client. Unset it in your shell
to force free-tier behavior despite a stale ambient value.

Pi adds or updates its declared Exa authentication headers only when the
resulting MCP URL exactly matches the declared Exa URL. Customized or
uncertain-ownership headers survive declaration changes; existing headers on
custom endpoints are left untouched. Unchanged declarations also preserve user
deletions.

**Audit existing custom Exa endpoints manually:** inspect the `exa` entry in
`~/.pi/agent/mcp.json` and remove or replace any `headers` that should not go to
that endpoint, especially `x-api-key: "${EXA_API_KEY}"`. Earlier reconciliation
could attach this default to a customized URL. Pi does not automatically remove
it because the repository cannot distinguish an old default from intentional
custom authentication. A custom endpoint with that header can receive your
runtime Exa key.

For one-off testing, override the provider for a single launch (this skips the
alias preflight):

```sh
SECRETSPEC_PROVIDER="dotenv://.env.local" opencode
SECRETSPEC_PROVIDER="dotenv://.env.local" pi
```
