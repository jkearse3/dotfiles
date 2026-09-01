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

A plaintext value never enters Nix evaluation, a derivation, a generated file,
process arguments, logs, or `/nix/store`. The wrappers require SecretSpec
`>= 0.18.0` (asserted at evaluation) from `nixpkgs-unstable`.

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
  reinterpret a failing provider as an uncommissioned machine.

## Backup and recovery

Values live in your chosen provider, so back them up its way (Keychain export,
`pass`'s git store). This repository keeps no recovery copy; if provider state
is lost, re-run commissioning and re-store each consumer's secrets.

## Consumers

Each consumer resolves one SecretSpec scope. The mechanism above is identical
for all of them; only the scope, its secrets, and their handling differ.

### OpenCode, OMP, and Pi (`EXA_API_KEY`)

OpenCode, OMP, and Pi resolve their respective `opencode`, `omp`, and `pi`
scopes, whose only secret is the optional `EXA_API_KEY` — an
[Exa](https://exa.ai) search key. Store, inspect, rotate, or remove it:

```sh
# Store or replace (hidden prompt; never on the command line).
secretspec set --file ~/dotfiles/secretspec.toml \
  --provider dotfiles --profile default EXA_API_KEY

# Check resolution without printing any value.
secretspec check --file ~/dotfiles/secretspec.toml \
  --provider dotfiles --profile default --scope opencode --explain
secretspec check --file ~/dotfiles/secretspec.toml \
  --provider dotfiles --profile default --scope omp --explain
secretspec check --file ~/dotfiles/secretspec.toml \
  --provider dotfiles --profile default --scope pi --explain

# Remove it (free tier resumes).
secretspec delete --file ~/dotfiles/secretspec.toml \
  --provider dotfiles --profile default EXA_API_KEY
```

`EXA_API_KEY` is `required = false`, so it is not needed to commission a
machine. With no stored value, all three clients still start on Exa's free tier:
`OPENCODE_ENABLE_EXA=1` remains unconditional, OMP uses its built-in Exa
integration, and Pi sends an empty `x-api-key` header that Exa treats as
anonymous access. The key raises quota; it does not gate search. A stored
provider value wins over an ambient `EXA_API_KEY`; with no stored value, an
ambient one survives into any client. Unset it in your shell to force free-tier
behavior despite a stale ambient value.

For one-off testing, override the provider for a single launch (this skips the
alias preflight):

```sh
SECRETSPEC_PROVIDER="dotenv://.env.local" opencode
SECRETSPEC_PROVIDER="dotenv://.env.local" omp
SECRETSPEC_PROVIDER="dotenv://.env.local" pi
```
