# SSH And Commit Signing

## Model

Each Mac reaches GitHub and signs commits with its own key, held in the Mac's
Secure Enclave (see [Secure Enclave Key](#secure-enclave-key)). The key needs no
approval and cannot be copied off the Mac. GitHub SSH and commit signing use
only that key: there is no fallback, so a Mac without it cannot reach GitHub
over SSH or sign until `bootstrap/git-key.sh` has run.

1Password serves SSH to every other host. Each machine that needs it has a
dedicated vault containing only the SSH keys active on that machine.
Machine-local `agent.toml` selects the vault by UUID; Home Manager configures
the agent socket, OpenSSH, Git, Jujutsu, and nono.

One key both authenticates and signs for the GitHub account it is added to:

- As an authentication key, it lets the account fetch and push.
- As a signing key, it makes GitHub show commits it signed as `Verified` for
  that account.

Multiple author identities can share the key when they use the same GitHub
account, as the work identity does. The current configuration supports one
GitHub account.

The local interface is:

- `~/.ssh/git_secure_enclave` and its `.pub`: the Secure Enclave key's handle
  and public key, used for GitHub.
- `~/.1password/agent.sock`: normalized 1Password agent socket, used for other
  hosts.
- `~/.config/1Password/ssh/agent.toml`: machine-vault selector.

Vault UUIDs and key contents must not enter Git or the Nix store. The
`~/.ssh/github_personal_authentication.pub` and
`~/.ssh/github_personal_signing.pub` selectors, and the 1Password GitHub keys
they selected, are no longer used.

## Provision A Machine

Give the Mac its Secure Enclave key with `bootstrap/git-key.sh` before the first
Nix command that evaluates this flake, as
[Installation](installation.md#provision-github-ssh-access) describes. Nix needs
the key to fetch `dotfiles-private` when it evaluates the flake.

Only a Mac that needs SSH to other hosts needs 1Password:

1. Enable the 1Password SSH agent.
2. Create a dedicated vault for the machine and its keys for those hosts.
3. Configure 1Password to approve per application, so one approval covers every
   tab of a terminal and an agent working unattended in a new tab is not blocked
   on a prompt. Never choose **Approve for all applications**.
4. Create machine-local `agent.toml` with the machine vault's UUID:

   ```toml
   [[ssh-keys]]
   vault = "<machine vault UUID>"
   ```

Vault membership is the agent allowlist. Keep unrelated and stale SSH keys out
of the machine vault. An empty `agent.toml` exposes no keys, malformed TOML
stops the agent, and removing the file restores 1Password's broader default
inventory.

Home Manager owns `~/.ssh/config`. Before the first switch, move any unmanaged
file to `~/.ssh/config.before-home-manager`; abort rather than overwrite an
existing backup, and retain it until verification succeeds.

## Secure Enclave Key

macOS creates the key inside the Mac's Secure Enclave, so it cannot be copied
off the Mac, and it signs without Touch ID or any approval, with the screen
locked too. OpenSSH reaches it through its handle, `~/.ssh/git_secure_enclave`,
a small file that holds no private key and is useless on any other Mac. The
certificate macOS creates for the key expires after a year, and the key keeps
signing after that; whether its handle can still be exported once the
certificate has expired is untested, so keep the handle files, which hold no
secret.

`bootstrap/git-key.sh` gives a Mac its key; it takes no arguments. It needs only
Nix: it runs `bootstrap/git_key.py` with the Python that `flake.lock` pins,
through `nix run --inputs-from`, which fetches nixpkgs without evaluating the
flake or fetching `dotfiles-private`, and the script runs macOS's own `sc_auth`
and `ssh-keygen`:

1. It creates the Secure Enclave identity labeled `git`, or reuses the one the
   Mac has.
2. With the screen unlocked, it exports the identity's handle to
   `~/.ssh/git_secure_enclave`, with the public key beside it.
3. It prints the public key, how to add it on GitHub, and an
   `export GIT_SSH_COMMAND=…` line for installing before Home Manager configures
   SSH.

The user adds the key at <https://github.com/settings/ssh/new> twice, signed in
to the GitHub account: once with key type `Authentication Key` and once with
`Signing Key`. GitHub lists a key only in the role it was added for, so one key
serves both roles only when it is added twice. The script never contacts GitHub.

A rerun reuses the key. When the handle already matches it, the script only
prints, so it also works with the screen locked or over SSH. It handles only a
Mac with no Secure Enclave identity or just the `git` one; it refuses when
`sc_auth list-ctk-identities` lists any other.

Nothing on the Mac carries a per-Mac name. The identity's label and Common Name
are both `git`, the same on every Mac. The user titles the key on each forge;
naming the Mac in each title, such as `Personal Laptop - Authentication`, makes
a lost Mac's entries easy to find, but nothing on the Mac reads the titles, so
renaming the Mac or a title never involves the key. The names say "git" rather
than "GitHub" because the key can authenticate and sign for any forge it is
added on. Another forge needs only its own SSH host block naming the same
handle, and the key added there. A dedicated authentication key for some forge
or account would be added beside this key, which keeps signing.

One key serves both roles because it is created without Touch ID, which
unattended work needs, so any process running as the user can use it; a second
key would add setup without adding safety. What it protects against is copying:
no file on the Mac, backup, or migration carries the private key.

An organization that enforces SAML single sign-on accepts the key only after it
is authorized for that organization in
[GitHub's SSH key settings](https://github.com/settings/keys).

A nono sandbox started before the handle existed does not see it, because nono
skips grants for missing paths; restart the sandbox after running the script.

### Procedures

Print the public key: rerun `bootstrap/git-key.sh`, or
`cat ~/.ssh/git_secure_enclave.pub`.

Rename the Mac or retitle an entry: nothing on the Mac changes. GitHub cannot
edit a key's title, so delete the entry in
[GitHub's SSH key settings](https://github.com/settings/keys) and add the same
public key again under the new title.

Replace the key:

```sh
sc_auth list-ctk-identities
sc_auth delete-ctk-identity -h <hash of the git identity>
rm ~/.ssh/git_secure_enclave ~/.ssh/git_secure_enclave.pub
bootstrap/git-key.sh
```

then add the new key's two entries and delete the old key's `Authentication Key`
entry in [GitHub's SSH key settings](https://github.com/settings/keys). Keep the
old key's `Signing Key` entry until every commit it signed is pushed, or for
good: GitHub checks a commit's signature when it is pushed, so deleting the
entry first leaves those commits `Unverified`, and the deleted key can sign
nothing new.

Retire the key: delete the identity and the handle files as above, and the
`Authentication Key` entry, keeping or deleting the `Signing Key` entry as
above.

Restore: a Mac restored from a backup, or migrated from another, can have a
handle or identity that names a key its Secure Enclave does not hold, and GitHub
SSH and signing fail. So can an export that fails with the screen unlocked.
Replace the key.

Another Secure Enclave identity: the script refuses when the Mac has one, such
as a smart-card identity, one another tool created, or the `git-personal`
identity an earlier version of this setup created. List them with
`sc_auth list-ctk-identities`, and delete one only after confirming what it
belongs to; a Mac that must keep another identity cannot use this setup.

A lost Mac: delete its `Authentication Key` entry in
[GitHub's SSH key settings](https://github.com/settings/keys) from any browser,
and its `Signing Key` entry too unless commits it signed are still to be pushed
from another machine.

### Existing Macs

A Mac that used 1Password for GitHub runs `bootstrap/git-key.sh` and adds the
two entries before the `switch-home` that moves GitHub to the key, because
afterwards GitHub SSH and signing use only the key. Until the handle exists,
`switch-home` refuses before changing anything and says to run the script, so
every Home Manager switch on that Mac waits for it. The script runs in any
state, because it skips the jj snapshot that the `nix` wrapper takes.

The switch repoints each jj workspace's repository config from the old signing
selector to the handle. Activating a configuration from before this change
afterwards leaves those workspaces unable to sign until `jjx ensure` runs in
each; meanwhile, `NIX_SKIP_JJ_SNAPSHOT=1` lets Nix commands run without the jj
snapshot.

The 1Password GitHub keys stay registered on GitHub, and the selector files stay
on disk, until the user deletes them.

## Verify

```sh
ssh -G github.com
ssh -T git@github.com
git ls-remote git@github.com:jkearse3/dotfiles-private >/dev/null
```

The effective GitHub configuration must use `git`, `identityagent none`,
`securitykeyprovider /usr/lib/ssh-keychain.dylib`, `IdentitiesOnly yes`, and
`~/.ssh/git_secure_enclave` as its only `identityfile`. GitHub's successful
`ssh -T` greeting still exits with status 1 because it provides no shell. In a
terminal, each connection prints
`Confirm user presence for key ECDSA-SK SHA256:…`; the key does not wait for a
touch, and ssh prints the notice for every key of its kind.

Create a disposable Git commit and confirm its raw object contains an SSH
signature made with no 1Password approval, also with 1Password locked or quit.
Jujutsu should sign own-authored commits as it writes them, so a push leaves
their commit IDs and committer timestamps unchanged, and sign any own-authored
mutable commit that is still unsigned before push. The user selects a disposable
remote, pushes the test commit, and confirms GitHub displays `Verified`.

Jujutsu signs every commit it writes, including working-copy snapshots, with the
Secure Enclave key, so neither a locked 1Password nor an unanswered prompt stops
it. Tooling that runs `jj` in the background, such as a prompt or editor
integration, must still pass `--ignore-working-copy` so it never snapshots and
never signs. The `nix` wrapper snapshots before every Nix command run inside a
jj repository, including the ones direnv's `use flake` runs;
`NIX_SKIP_JJ_SNAPSHOT=1` skips the snapshot (see
[Working-Copy Snapshots](architecture.md#working-copy-snapshots)).

## Remote Use

Remote work runs on the machine itself, in Rex and herdr sessions reached from
another computer or a phone: Rex through its own Tailscale pairing, herdr over
SSH. Commands in those panes use the machine's own keys, so no agent is
forwarded. Fetch, push, commit signing, and the snapshot before each Nix command
use the Secure Enclave key and need neither 1Password approval nor an unlocked
1Password. The key keeps working across reboots once the user has logged in at
the Mac.

SSH to other hosts still uses the machine's 1Password agent, whose approvals
stay per application: approve Rex and herdr once at the machine, and a pane
opened remotely later uses the keys without a prompt for as long as the approval
lasts. For that, 1Password must stay unlocked while the user is away, and a
locked 1Password can be unlocked only at the machine. These settings live in the
1Password app, which owns them; set them by hand on each machine that uses it:

- **Security → Auto-lock:** a timeout longer than the time spent away, and
  locking on sleep or screensaver turned off.
- **Developer → Remember key approval:** until 1Password locks, so one approval
  per application covers the whole session.

`sudo` asks for the password in the terminal (see
[Installation](installation.md#activate-nix-darwin)), so `switch-system` can be
answered from a remote pane.

When GitHub cannot be reached, a switch can read `dotfiles-private` from the
`~/dotfiles-private` checkout instead of fetching it over SSH. The checkout must
be current, and Nix does not see files created since the last `jj` command.

```sh
DOTFILES_PRIVATE_LOCAL=1 nix run .#switch-system
```

The machine must also stay awake and reachable: Rex and herdr cannot reach a
sleeping machine's sessions. This configuration does not manage that.

## Additional GitHub Accounts

This setup supports one GitHub account per Mac. GitHub attaches a key to one
account only, so another account would need its own key, a distinct SSH host
alias, URL routing for that account's repositories, and the corresponding VCS
identity scope, which this configuration does not provide. Author identities
that map to the existing GitHub account share the existing key.

## Recovery

If activation fails, restore `~/.ssh/config.before-home-manager`. If a machine
is lost, delete its Secure Enclave key's entries in
[GitHub's SSH key settings](https://github.com/settings/keys) from any browser,
as [Procedures](#procedures) describes, and archive its 1Password vault if it
has one.
