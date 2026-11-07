#!/usr/bin/env bash
# Copies the Herdr.app bundle from the Nix store to DEST, ad-hoc signs it, and
# registers it with Launch Services, so Spotlight, the Dock and Finder see a
# real app. Home Manager activation runs it after each switch. A store bundle
# or a symlink to one is not enough: Launch Services does not index
# applications inside the store, and a store copy cannot be signed in place.
#
# Usage: install-bundle.sh SOURCE DEST [LSREGISTER [CODESIGN]]
#   SOURCE      the bundle in the Nix store.
#   DEST        the installed bundle, `~/Applications/Herdr.app`.
#   LSREGISTER  the Launch Services registration tool, the system one unless
#               given; the fixtures in `install-bundle-test.sh` pass fakes for
#               it and CODESIGN.
#   CODESIGN    the signing tool, `/usr/bin/codesign` unless given.
#
# It replaces DEST only when DEST is missing or was copied from a different
# SOURCE, so a switch with an unchanged package leaves the bundle untouched.
# The copy records SOURCE in a marker file. It touches nothing else beside
# DEST. On failure it removes the marker and exits nonzero, so activation
# reports the failure and the next switch tries again.
set -euo pipefail

source_bundle=${1:?usage: install-bundle.sh SOURCE DEST [LSREGISTER [CODESIGN]]}
dest=${2:?usage: install-bundle.sh SOURCE DEST [LSREGISTER [CODESIGN]]}
lsregister=${3:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}
codesign=${4:-/usr/bin/codesign}

# The marker sits in `Contents/Resources/`, so the signature seals it: a file
# directly in `Contents/` makes `codesign` refuse the bundle.
marker="$dest/Contents/Resources/dotfiles-source"

if [[ ! -L $dest && -d $dest && -f $marker && $(<"$marker") == "$source_bundle" ]]; then
	exit 0
fi

if [[ -L $dest || -f $dest ]]; then
	rm -f -- "$dest"
elif [[ -e $dest ]]; then
	# A copy from the store keeps its read-only modes, so it cannot be removed
	# until it is writable again.
	chmod -R u+w -- "$dest"
	rm -rf -- "$dest"
fi

mkdir -p -- "${dest%/*}"
cp -R -- "$source_bundle" "$dest"
chmod -R u+w -- "$dest"
printf '%s\n' "$source_bundle" >"$marker"

# A running Herdr keeps the executable it started from, so replacing the
# bundle does not interrupt it; it uses the new one after it restarts.
if ! "$codesign" --force --sign - "$dest" || ! "$lsregister" -f "$dest"; then
	rm -f -- "$marker"
	echo "Could not sign or register $dest; the next switch will install it again." >&2
	exit 1
fi
