# SSH And Commit Signing

## Model

1Password owns private keys and approval policy. Each machine has a dedicated
vault containing only the SSH keys active on that machine. Machine-local
`agent.toml` selects the vault by UUID; Home Manager configures the agent
socket, OpenSSH, Git, Jujutsu, and nono.

Keys have separate roles:

- An authentication key identifies a GitHub account for fetch and push.
- A signing key creates commit signatures; GitHub associates them with the
  account where its public key is registered.

Multiple author identities can reuse the same authentication/signing pair when
they use the same GitHub account. A separate GitHub account normally needs its
own pair, plus explicit SSH and repository routing. The current configuration
supports one GitHub account; work signing remains disabled until its GitHub
account is known.

The local interface for the current account is:

- `~/.1password/agent.sock`: normalized 1Password agent socket.
- `~/.ssh/github_personal_authentication.pub`: authentication selector.
- `~/.ssh/github_personal_signing.pub`: signing selector.
- `~/.config/1Password/ssh/agent.toml`: machine-vault selector.

The `.pub` files select matching private keys held by 1Password. They contain no
private material, but remain machine-local and uncommitted. Vault UUIDs and key
contents must not enter Git or the Nix store.

## Provision A Machine

1. Enable the 1Password SSH agent.
2. Create a dedicated vault for the machine.
3. Create separate authentication and signing keys in that vault.
4. Register the authentication key with GitHub as an authentication key and the
   signing key as a signing key.
5. Save their public keys to the selector paths above.
6. Configure 1Password to approve per application and terminal session. Never
   choose **Approve for all applications**.
7. Create machine-local `agent.toml` with the machine vault's UUID:

   ```toml
   [[ssh-keys]]
   vault = "<machine vault UUID>"
   ```

Vault membership is the agent allowlist. Keep unrelated and stale SSH keys out
of the machine vault. An empty `agent.toml` exposes no keys, malformed TOML
stops the agent, and removing the file restores 1Password's broader default
inventory.

Before the first activation, `x.sh` uses 1Password's native Darwin socket when
the normalized socket does not exist. After activation, Home Manager's
normalized socket takes precedence.

```sh
./x.sh nix-blueprints
./x.sh nix-switch-home --blueprint <blueprint-id>
```

Home Manager owns `~/.ssh/config`. Before the first switch, move any unmanaged
file to `~/.ssh/config.before-home-manager`; abort rather than overwrite an
existing backup, and retain it until verification succeeds.

## Verify

```sh
ssh -G github.com
ssh -T git@github.com
git ls-remote git@github.com:jkearse3/dotfiles-private >/dev/null
```

The effective GitHub configuration must use `git`, the normalized agent socket,
the authentication selector, and `IdentitiesOnly yes`. GitHub's successful
`ssh -T` greeting still exits with status 1 because it provides no shell.

Create a disposable Git commit and confirm its raw object contains an SSH
signature. Repeat with `SSH_AUTH_SOCK` unset to confirm the signing wrapper uses
the normalized socket. Jujutsu should leave ordinary rewrites unsigned and sign
own-authored mutable commits before push. The user selects a disposable remote,
pushes the test commit, and confirms GitHub displays `Verified`.

## Additional GitHub Accounts

Do not add only a signing key for another GitHub account. Provision an
authentication/signing pair, public selectors, a distinct SSH host alias, URL
routing for that account's repositories, and the corresponding VCS identity
scope. Author identities that map to the existing GitHub account can reuse the
existing pair instead.

## Recovery

If activation fails, restore `~/.ssh/config.before-home-manager`. If a machine
is lost, revoke its GitHub keys and archive its 1Password vault.
