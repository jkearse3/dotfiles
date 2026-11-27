# Fresh Darwin Installation

This guide bootstraps a fresh Apple Silicon Mac into the nix-darwin system and
Home Manager configurations managed by this repository.

## Requirements

The current blueprints require:

- An Apple Silicon Mac. The repository only exports `aarch64-darwin`
  configurations.
- A macOS administrator account named `johnnie` with home directory
  `/Users/johnnie`.
- Network access to GitHub, Nix caches, and Homebrew.
- A GitHub account with access to `jkearse3/dotfiles-private`, to which the
  Mac's Secure Enclave key is added.

The configuration does not create the macOS account. Add or change a blueprint
before installation if the username, home directory, or platform differs.

## Install Bootstrap Tools

Install [Homebrew](https://brew.sh/). Allow its installer to install the Xcode
Command Line Tools if macOS requests them. On Apple Silicon, Homebrew must be
available at `/opt/homebrew`.

Install [Determinate Nix](https://determinate.systems/nix-installer/) using its
current vendor installer. Determinate manages the Nix daemon; nix-darwin leaves
daemon management disabled intentionally.

Open a new terminal and verify both tools:

```sh
/opt/homebrew/bin/brew --version
nix --version
```

Clone the public repository. The commands in this guide use `~/dotfiles`, but
any location works:

```sh
git clone https://github.com/jkearse3/dotfiles.git "$HOME/dotfiles"
cd "$HOME/dotfiles"
```

## Provision GitHub SSH Access

The flake includes `dotfiles-private` as an SSH input, and Nix fetches it before
it evaluates anything, so the Mac needs a key GitHub accepts before the first
`nix run .#…` or `nix develop` invocation. The Mac's key lives in its Secure
Enclave (see [Secure Enclave Key](ssh.md#secure-enclave-key)); with the screen
unlocked, create it:

```sh
bootstrap/git-key.sh
```

The script needs only Nix, installed above: it runs with the Python that this
repository's `flake.lock` pins and does not fetch `dotfiles-private`. It prints
the public key and two entries to add at <https://github.com/settings/ssh/new>,
signed in to the GitHub account: the same key once as an `Authentication Key`
and once as a `Signing Key`, each with a title you choose for this Mac. It ends
with an `export GIT_SSH_COMMAND=…` line; run that line in the terminal that will
run the remaining steps, up to Home Manager activation, so Nix fetches
`dotfiles-private` with the key.

Verify that GitHub accepts the key for the private repository:

```sh
sh -c "$GIT_SSH_COMMAND -T git@github.com"
git ls-remote git@github.com:jkearse3/dotfiles-private >/dev/null
```

On the first connection, compare the presented host-key fingerprint with
[GitHub's published SSH key fingerprints](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)
before accepting it.

The final command is the decisive access check. A successful `ssh -T` greeting
from GitHub still exits with status 1 because GitHub does not provide a shell.

A Mac that needs SSH to hosts other than GitHub also needs 1Password; see
[Provision A Machine](ssh.md#provision-a-machine).

## Prepare Home Manager Paths

Home Manager refuses to overwrite unmanaged files. A fresh account usually has
few conflicts, but inspect any existing shell, SSH, Git, Jujutsu, editor, and
agent configuration before activation.

Home Manager owns `~/.ssh/config`. If it already exists, move it aside before
the first Home Manager switch:

```sh
if [[ -e "$HOME/.ssh/config" ]]; then
  test ! -e "$HOME/.ssh/config.before-home-manager" && \
    mv "$HOME/.ssh/config" "$HOME/.ssh/config.before-home-manager"
fi
```

If the backup already exists, the guard leaves both files untouched. Resolve
that conflict explicitly rather than overwriting either file. Keep the backup
until SSH verification succeeds. Preserve and move aside any other unmanaged
file that Home Manager reports as a collision rather than overwriting it.

## Initialize The Repository

Repository commands are plain Nix commands and flake apps, run from the
repository root; the apps bring their own Bash, nh, and other tools, so a fresh
machine needs only Nix. Until Home Manager writes the binary cache into the
user's Nix configuration, pass `--accept-flake-config` so Nix uses the cache
declared in `flake.nix`.

The development shell supplies Jujutsu and `jjx` before Home Manager installs
them:

```sh
cd "$HOME/dotfiles"
nix develop --accept-flake-config --command jjx ensure
```

`jjx ensure` creates the colocated Jujutsu workspace that the `nix` wrapper
snapshots and `nix run .#flake-update` commits to.

List the available blueprints:

```sh
nix eval --accept-flake-config .#blueprints --apply builtins.attrNames
```

The current choices are:

- `laptop-dev-default`: the development workstation without work-specific VCS
  identity.
- `laptop-dev-work`: the same workstation with repository-scoped work VCS
  identity from `dotfiles-private`.

Choose one blueprint for both system and Home Manager activation:

```sh
blueprint=laptop-dev-default
```

## Activate nix-darwin

Build, inspect, and activate the system configuration:

```sh
nix run --accept-flake-config .#switch-system -- --blueprint "$blueprint"
```

The activation requests administrator access through `sudo`. It configures
nix-darwin, makes Fish the user's login shell, and asks Homebrew to install the
declared applications. Homebrew does not automatically update, upgrade, or
remove other packages during activation. `sudo` asks for the user's password in
the terminal rather than through Touch ID, so a Rex or herdr pane reached from
another device can answer it (see [Remote Use](ssh.md#remote-use)).

The Home Manager and nix-darwin outputs are independent, but system-first is the
documented bootstrap order. The system activation creates the user's
`XDG_RUNTIME_DIR` under `/var/run/user`; Home Manager exports the variable only
once that directory exists, and warns during activation until it does.

## Activate Home Manager

Build, inspect, and activate the selected user's configuration:

```sh
nix run --accept-flake-config .#switch-home -- --blueprint "$blueprint"
```

Home Manager activates without `sudo` and writes the selected blueprint to:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/blueprint-id
```

Later build and switch apps read this marker, so they no longer need an explicit
`--blueprint` argument.

Open a new terminal after activation. Home Manager cannot update the environment
of the shell that launched it; a new login shell loads the managed profile,
whose SSH configuration uses the Secure Enclave key for GitHub, so it no longer
needs the `GIT_SSH_COMMAND` export. The profile also selects the normalized
1Password agent socket for other hosts and puts the `nix` wrapper that snapshots
the Jujutsu working copy ahead of the real Nix (see
[Working-Copy Snapshots](architecture.md#working-copy-snapshots)).

## Verify The Installation

Managed Ghostty sessions start in Fish, while the verification snippets below
use Bash syntax. Start the managed Bash first:

```sh
bash
```

Verify the system generation, the Home Manager marker, that every blueprint
evaluates, and that the selected Home Manager configuration builds:

```sh
cd "$HOME/dotfiles"

test -e /run/current-system
test -s "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/blueprint-id"

nix build --no-link .#eval-blueprints
nix run .#build-home
```

Verify the managed GitHub SSH configuration and private repository access:

```sh
ssh -G github.com
ssh -T git@github.com
git ls-remote git@github.com:jkearse3/dotfiles-private >/dev/null
```

The effective GitHub configuration should use user `git`, `identityagent none`,
`securitykeyprovider /usr/lib/ssh-keychain.dylib`, `IdentitiesOnly yes`, and
`~/.ssh/git_secure_enclave` as its only `identityfile`.

Verify that Git signs with the Secure Enclave key configured by Home Manager:

```sh
signing_test="$(mktemp -d)"
git -C "$signing_test" init
git -C "$signing_test" commit --allow-empty -m "verify SSH signing"
git -C "$signing_test" cat-file commit HEAD | grep '^gpgsig '
rm -rf -- "$signing_test"
```

The commit should contain a `gpgsig` header and need no 1Password approval.
Complete the GitHub `Verified` check described in
[SSH and commit signing](ssh.md#verify) before relying on signing for published
work. Run `exit` when verification is complete to return to Fish.

## Commission Optional Secrets

Secrets are not required to evaluate or activate either configuration. To use
secret-backed launchers, map the machine-local `dotfiles` provider alias after
Home Manager activation:

```sh
secretspec config global provider add dotfiles keyring://
secretspec config global provider list
```

See [Secrets](secrets.md) for consumer-specific values, verification, and
recovery.

## Troubleshooting

### Private flake access fails

Private flake access fails until GitHub lists the Mac's Secure Enclave key as an
authentication key. Rerun `bootstrap/git-key.sh` to print the key, confirm
GitHub's SSH key settings list it as an `Authentication Key`, rerun the printed
`export GIT_SSH_COMMAND=…` line in the shell that runs Nix, and rerun the
private `git ls-remote` check. When the script cannot export the key, follow the
restore procedure in [Procedures](ssh.md#procedures).

### No blueprint is selected

First-time activation requires `--blueprint <blueprint-id>`. Home Manager writes
the marker used by later commands; nix-darwin activation alone does not create
it.

### `nix run` fails before the app runs

`nix run` evaluates the flake before the app starts, so a failure there is
usually private flake access: see
[Private flake access fails](#private-flake-access-fails).

### `switch-system` fails to activate nix-darwin

`nix run .#switch-system` activates through nh's `darwin switch`. If it fails on
a machine that has never activated nix-darwin, activate once with nix-darwin
directly, then return to `nix run .#switch-system`. nix-darwin requires system
activation to run as root, and root cannot use the user's Secure Enclave key, so
it cannot fetch `dotfiles-private` itself: clone it as the user first, with the
`GIT_SSH_COMMAND` export in place, and pass the checkout:

```sh
git clone git@github.com:jkearse3/dotfiles-private.git "$HOME/dotfiles-private"
sudo nix run nix-darwin/master#darwin-rebuild -- switch --flake .#<darwinConfigurationName> \
  --override-input dotfiles-private "path:$HOME/dotfiles-private"
```

`nix eval --json .#blueprints` shows each blueprint's `darwinConfigurationName`.
On a machine that has activated nix-darwin before, run
`sudo /run/current-system/sw/bin/darwin-rebuild switch --flake .#<darwinConfigurationName>`
instead, with the same `--override-input`.

### Home Manager reports an existing file

Move the unmanaged file to a clearly named backup, rerun the Home Manager
switch, compare the managed result with the backup, and retain the backup until
verification succeeds.
