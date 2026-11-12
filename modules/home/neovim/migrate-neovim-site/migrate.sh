#!/usr/bin/env bash

# Removes the plugins and tree-sitter files that vim.pack and nvim-treesitter
# left in Neovim's site directory, SITE_DIR, before Home Manager installed them
# from Nix into SITE_DIR/pack/hm. Removes exactly pack/core, parser,
# parser-info, and queries, prints one line per directory it removes, and
# prints nothing when none of them exists, so a second run is silent.

set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "usage: migrate-neovim-site <SITE_DIR>" >&2
	exit 2
fi

site_dir=$1

for leftover in pack/core parser parser-info queries; do
	path="$site_dir/$leftover"
	if [[ -e $path || -L $path ]]; then
		rm -rf -- "$path"
		echo "removed $path"
	fi
done
