#!/usr/bin/env bash
# Copies the personal layouts and mods this repository owns into the Herdr
# app's home as regular files and directories. Home Manager activation runs
# it on each switch, so a change reaches the running window only then, and
# whole: each mod folder and layout file is swapped in by one rename.
#
# Usage: deploy.sh TREE APP_HOME SHIPPED
#   TREE      the deploy tree in the Nix store: `mods/<name>/` for each
#             personal mod and `layouts/<file>` for each personal layout.
#   APP_HOME  the app's home, `~/.config/herdr-app`.
#   SHIPPED   a file listing the app's shipped entries, one `mods/<name>` or
#             `layouts/<file>` per line; it never removes one of them.
#
# The entries it owns are recorded in `APP_HOME/dotfiles-owned.txt`, one
# `mods/<name>` or `layouts/<file>` per line. It reads only lines of that
# shape whose name does not start with a dot, so a damaged manifest cannot
# point it at app state such as `layouts/.state`, or outside those folders.
# Each switch deploys TREE's entries and removes the owned entries TREE no
# longer has. Everything else in APP_HOME (shipped mods and layouts, app
# state, the escape hatch's renamed layouts, other user files) is left alone.
#
# An entry that already holds TREE's content is not touched, so a switch
# without changes sends the window no reload. A mod folder counts as
# unchanged even with the `gpui-kit.d.ts` and `jsconfig.json` the app writes
# into every mod it loads. Any other difference, including an edit to the
# deployed copy, is replaced with TREE's content.
#
# A changed entry is copied to the dot-named sibling `.<name>.dotfiles-new`
# and swapped with the old entry by `mv --exchange`, one atomic rename, so the
# window never loads a half-written mod. The app ignores dot-named mod folders
# and files inside them (herdr-app `src/mods.rs` `scan_dir`, `src/files.rs`
# `mod_file_counts`) and lists only `*.json` layouts. The swap also replaces a
# symlink left at the target, such as an old Home Manager link, without
# touching what it points to.
#
# The manifest is rewritten with the union of the old and new entries before
# any copy, so an interrupted switch still owns what it wrote; it exits
# nonzero on any failure, and the next switch finishes the work.
set -euo pipefail

usage='usage: deploy.sh TREE APP_HOME SHIPPED'
tree=${1:?$usage}
app_home=${2:?$usage}
shipped=${3:?$usage}

manifest="$app_home/dotfiles-owned.txt"

# Removes PATH, whether a file, a symlink (not its target) or a directory a
# store copy left read-only.
remove_entry() {
	local path=$1

	if [[ -L $path || -f $path ]]; then
		rm -f -- "$path"
	elif [[ -e $path ]]; then
		chmod -R u+w -- "$path"
		rm -rf -- "$path"
	fi
}

# Prints the dot-named sibling of TARGET that a new copy is staged in.
staging_path() {
	local target=$1

	printf '%s\n' "${target%/*}/.${target##*/}.dotfiles-new"
}

# Succeeds when TARGET is a real file or directory with SOURCE's content,
# ignoring the typings the app writes at a mod folder's top level.
is_deployed() {
	local source=$1 target=$2

	[[ ! -L $target ]] || return 1
	if [[ -f $source ]]; then
		[[ -f $target ]] && cmp -s -- "$source" "$target"
		return
	fi
	[[ -d $target ]] || return 1

	local differences status=0
	differences=$(diff -rq --no-dereference -- "$source" "$target") || status=$?
	((status <= 1)) || return 1
	local line
	while IFS= read -r line; do
		case $line in
		"" | "Only in $target: gpui-kit.d.ts" | "Only in $target: jsconfig.json") ;;
		*) return 1 ;;
		esac
	done <<<"$differences"
}

# Makes `APP_HOME/ENTRY` a writable copy of `TREE/ENTRY` unless it already is.
deploy_entry() {
	local entry=$1
	local source="$tree/$entry" target="$app_home/$entry"
	local staging
	staging=$(staging_path "$target")

	remove_entry "$staging"
	if is_deployed "$source" "$target"; then
		return
	fi

	cp -R -- "$source" "$staging"
	chmod -R u+w -- "$staging"
	if [[ -e $target || -L $target ]]; then
		mv --exchange -T -- "$staging" "$target"
		remove_entry "$staging"
	else
		mv -T -- "$staging" "$target"
	fi
}

# Prints the manifest's well-formed entries.
read_manifest() {
	[[ -f $manifest ]] || return 0

	local line
	while IFS= read -r line || [[ -n $line ]]; do
		if [[ $line =~ ^(mods|layouts)/[^./][^/]*$ ]]; then
			printf '%s\n' "$line"
		fi
	done <"$manifest"
}

# Replaces the manifest with the given entries in one rename.
write_manifest() {
	if (($# > 0)); then
		printf '%s\n' "$@"
	fi | LC_ALL=C sort -u >"$app_home/.dotfiles-owned.txt.new"
	mv -f -- "$app_home/.dotfiles-owned.txt.new" "$manifest"
}

shopt -s nullglob

entries=()
for path in "$tree"/mods/*/; do
	path=${path%/}
	entries+=("mods/${path##*/}")
done
for path in "$tree"/layouts/*; do
	entries+=("layouts/${path##*/}")
done

mkdir -p -- "$app_home/mods" "$app_home/layouts"
old_entries=()
old_listing=$(read_manifest)
if [[ -n $old_listing ]]; then
	mapfile -t old_entries <<<"$old_listing"
fi
write_manifest "${old_entries[@]}" "${entries[@]}"

for entry in "${entries[@]}"; do
	deploy_entry "$entry"
done

declare -A is_current=() is_shipped=()
for entry in "${entries[@]}"; do
	is_current[$entry]=1
done
while IFS= read -r entry || [[ -n $entry ]]; do
	is_shipped[$entry]=1
done <"$shipped"
for entry in "${old_entries[@]}"; do
	if [[ -z ${is_current[$entry]-} && -z ${is_shipped[$entry]-} ]]; then
		remove_entry "$(staging_path "$app_home/$entry")"
		remove_entry "$app_home/$entry"
	fi
done

write_manifest "${entries[@]}"
