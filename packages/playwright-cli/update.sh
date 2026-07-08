#!/usr/bin/env bash

set -euo pipefail

usage() {
	cat <<'EOF'
usage: ./update.sh [--latest | --version VERSION] [--rev REV] [--dry-run]

Refresh package.nix pins for the package-local playwright-cli package.

Options:
  --latest          Use the latest upstream GitHub release.
  --version VERSION  Package version to write. Defaults to the current pin.
  --rev REV          Git revision to fetch. Defaults to the current pin.
  --dry-run          Print the computed pins without editing package.nix.
  -h, --help         Show this help text.

The update path refreshes the GitHub source hash and npmDepsHash. The help and
dry-run paths do not mutate the pinned package.
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_nix="$script_dir/package.nix"

current_value() {
	local name=$1
	sed -nE "s/^[[:space:]]*$name = \"([^\"]+)\";$/\\1/p" "$package_nix" | head -n1
}

github_api() {
	local url=$1
	nix eval --raw --impure --expr "builtins.readFile (builtins.fetchurl \"$url\")"
}

version="$(current_value version)"
rev="$(current_value rev)"
dry_run=0
latest=0

while [[ $# -gt 0 ]]; do
	case "$1" in
	--latest)
		latest=1
		shift
		;;
	--version)
		version="${2:?missing value for --version}"
		shift 2
		;;
	--rev)
		rev="${2:?missing value for --rev}"
		shift 2
		;;
	--dry-run)
		dry_run=1
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "error: unknown argument: $1" >&2
		usage >&2
		exit 2
		;;
	esac
done

if [[ $latest -eq 1 ]]; then
	release_json="$(github_api https://api.github.com/repos/microsoft/playwright-cli/releases/latest)"
	tag="$(jq -r .tag_name <<<"$release_json")"
	if [[ -z $tag || $tag == null ]]; then
		echo "error: failed to discover latest GitHub release tag" >&2
		exit 1
	fi
	tag_ref_json="$(github_api "https://api.github.com/repos/microsoft/playwright-cli/git/ref/tags/$tag")"
	tag_type="$(jq -r .object.type <<<"$tag_ref_json")"
	tag_sha="$(jq -r .object.sha <<<"$tag_ref_json")"
	case "$tag_type" in
	commit)
		rev="$tag_sha"
		;;
	tag)
		tag_json="$(github_api "https://api.github.com/repos/microsoft/playwright-cli/git/tags/$tag_sha")"
		rev="$(jq -r .object.sha <<<"$tag_json")"
		;;
	*)
		rev=""
		;;
	esac
	if [[ -z $rev ]]; then
		echo "error: failed to resolve release tag $tag" >&2
		exit 1
	fi
	version="${tag#v}"
fi

if [[ -z $version || -z $rev ]]; then
	echo "error: failed to read current version or rev from $package_nix" >&2
	exit 1
fi

src_hash="$(nix flake prefetch --json "github:microsoft/playwright-cli/$rev" | jq -r .hash)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
tmp_package="$tmpdir/package.nix"
cp "$package_nix" "$tmp_package"

VERSION=$version REV=$rev SRC_HASH=$src_hash perl -0pi -e '
	s/version = "[^"]+";/version = "$ENV{VERSION}";/;
	s/rev = "[^"]+";/rev = "$ENV{REV}";/;
	s/hash = "[^"]+";/hash = "$ENV{SRC_HASH}";/;
	s/npmDepsHash = "[^"]+";/npmDepsHash = pkgs.lib.fakeHash;/;
' "$tmp_package"

set +e
build_output="$(nix build --no-link --impure --expr "let pkgs = import <nixpkgs> {}; in import $tmp_package { inherit pkgs; }" 2>&1)"
build_status=$?
set -e

if [[ $build_status -eq 0 ]]; then
	echo "error: npmDepsHash probe unexpectedly succeeded" >&2
	exit 1
fi

npm_deps_hash="$(printf '%s\n' "$build_output" | sed -nE 's/^[[:space:]]*got:[[:space:]]*(sha256-[^[:space:]]+)$/\1/p' | tail -n1)"

if [[ -z $npm_deps_hash ]]; then
	echo "error: failed to discover npmDepsHash" >&2
	printf '%s\n' "$build_output" >&2
	exit 1
fi

cat <<EOF
version = $version
rev = $rev
hash = $src_hash
npmDepsHash = $npm_deps_hash
EOF

if [[ $dry_run -eq 1 ]]; then
	exit 0
fi

VERSION=$version REV=$rev SRC_HASH=$src_hash NPM_DEPS_HASH=$npm_deps_hash perl -0pi -e '
	s/version = "[^"]+";/version = "$ENV{VERSION}";/;
	s/rev = "[^"]+";/rev = "$ENV{REV}";/;
	s/hash = "[^"]+";/hash = "$ENV{SRC_HASH}";/;
	s/npmDepsHash = "[^"]+";/npmDepsHash = "$ENV{NPM_DEPS_HASH}";/;
' "$package_nix"
