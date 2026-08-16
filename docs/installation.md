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
- GitHub access to `jkearse3/dotfiles-private` through the 1Password SSH agent.

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

Clone the public repository into the required location:

```sh
git clone https://github.com/jkearse3/dotfiles.git "$HOME/dotfiles"
cd "$HOME/dotfiles"
```

Normal Home Manager activation creates editable links into `~/dotfiles`. Do not
move or delete this checkout after activation. Use `nix-switch-home-locked` only
when store-backed, non-editable Home Manager sources are specifically needed.

## Provision GitHub SSH Access

The flake includes `dotfiles-private` as an SSH input. Provision access before
the first `nix develop` invocation; the system configuration cannot install and
configure 1Password until after Nix has evaluated the flake.

Install 1Password manually for this bootstrap:

```sh
/opt/homebrew/bin/brew install --cask 1password
```

In 1Password and GitHub:

1. Sign in to 1Password and enable its SSH agent.
2. Create a dedicated vault for this machine.
3. Create separate SSH authentication and signing keys in that vault.
4. Register the authentication key with the GitHub account that can read
   `jkearse3/dotfiles-private`.
5. Register the signing key with GitHub as a signing key.
6. Configure 1Password to approve keys per application and terminal session.
   Never choose **Approve for all applications**.

Create `~/.config/1Password/ssh/agent.toml` with the machine vault UUID:

```sh
mkdir -p "$HOME/.ssh" "$HOME/.config/1Password/ssh"
chmod 700 "$HOME/.ssh"
```

```toml
[[ssh-keys]]
vault = "<machine vault UUID>"
```

Save the corresponding public keys at these machine-local paths:

```text
~/.ssh/github_personal_authentication.pub
~/.ssh/github_personal_signing.pub
```

Only public keys belong in these files. Private keys remain in 1Password and are
exposed to OpenSSH through the agent socket. See
[SSH and commit signing](ssh.md) for the complete key model and recovery
procedure.

Export the native 1Password agent socket in the terminal that will run the
bootstrap commands:

```sh
export SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
```

Verify that the agent exposes the authentication key and that GitHub authorizes
it for the private repository:

```sh
ssh-add -L
ssh -T git@github.com
git ls-remote git@github.com:jkearse3/dotfiles-private >/dev/null
```

On the first connection, compare the presented host-key fingerprint with
[GitHub's published SSH key fingerprints](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)
before accepting it.

The final command is the decisive access check. A successful `ssh -T` greeting
from GitHub still exits with status 1 because GitHub does not provide a shell.

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

The development shell supplies the modern Bash, Jujutsu, `jq`, `nvd`, and other
tools used by `x.sh`. Accept the repository's flake configuration explicitly on
a new Nix installation:

```sh
cd "$HOME/dotfiles"
nix develop --accept-flake-config --command jj-ensure
```

`jj-ensure` creates the colocated Jujutsu workspace required by `x.sh`.

List the available blueprints:

```sh
nix develop --accept-flake-config --command ./x.sh nix-blueprints
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
nix develop --accept-flake-config --command \
  ./x.sh nix-switch-system --blueprint "$blueprint"
```

The activation requests administrator access through `sudo`. It configures
nix-darwin, enables Fish system integration and Touch ID for `sudo`, and asks
Homebrew to install the declared applications. Homebrew does not automatically
update, upgrade, or remove other packages during activation.

The Home Manager and nix-darwin outputs are independent, but system-first is the
documented bootstrap order.

## Activate Home Manager

Build, inspect, and activate the selected user's configuration:

```sh
nix develop --accept-flake-config --command \
  ./x.sh nix-switch-home --blueprint "$blueprint"
```

Home Manager activates without `sudo` and writes the selected blueprint to:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/blueprint-id
```

Later `./x.sh` commands read this marker, so they no longer need an explicit
`--blueprint` argument.

Open a new terminal after activation. Home Manager cannot update the environment
of the shell that launched it; a new login shell loads the managed profile,
exposes modern Bash on `PATH`, and selects the normalized 1Password agent
socket.

## Verify The Installation

Managed Ghostty sessions start in Fish, while the verification snippets below
use Bash syntax. Start the managed Bash first:

```sh
bash
```

Verify the system generation, Home Manager marker, and both flake outputs:

```sh
cd "$HOME/dotfiles"

test -e /run/current-system
test -s "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/blueprint-id"

./x.sh nix-eval-system
./x.sh nix-eval-home
```

Verify the managed GitHub SSH configuration and private repository access:

```sh
ssh -G github.com
ssh -T git@github.com
git ls-remote git@github.com:jkearse3/dotfiles-private >/dev/null
```

The effective GitHub configuration should use user `git`, the normalized
`~/.1password/agent.sock`, the authentication selector, and
`IdentitiesOnly yes`.

Verify that Git can use the separate signing key configured by Home Manager:

```sh
signing_test="$(mktemp -d)"
git -C "$signing_test" init
git -C "$signing_test" commit --allow-empty -m "verify SSH signing"
git -C "$signing_test" cat-file commit HEAD | grep '^gpgsig '
rm -rf -- "$signing_test"
```

The commit should request 1Password approval and contain a `gpgsig` header.
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

Re-export the native 1Password socket and rerun `ssh-add -L` and the private
`git ls-remote` check. Confirm that `agent.toml` selects the intended vault and
that GitHub has the matching authentication public key.

### No blueprint is selected

First-time activation requires `--blueprint <blueprint-id>`. Home Manager writes
the marker used by later commands; nix-darwin activation alone does not create
it.

### `x.sh` rejects the macOS Bash version

Before Home Manager activation, invoke `x.sh` through `nix develop` as shown
above. After activation, open a new terminal so the managed profile's Bash is on
`PATH`.

### Home Manager reports an existing file

Move the unmanaged file to a clearly named backup, rerun the Home Manager
switch, compare the managed result with the backup, and retain the backup until
verification succeeds.

### Editable configuration links are broken

Restore the repository at `~/dotfiles` and rerun `./x.sh nix-switch-home`. The
normal configuration intentionally links managed source files to this checkout.
