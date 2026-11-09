#!/usr/bin/env bash
# Fixtures for `deploy.sh`, run as a build gate by the derivation in
# `deploy.nix`. Takes the deploy executable under test as its only argument.
# Each fixture deploys a read-only tree, as one in the Nix store is, into a
# scratch app home that also holds shipped mods and layouts, app state and an
# unowned mod, which must come through every deploy unchanged.
set -euo pipefail
export LC_ALL=C

deploy=${1:?usage: deploy-test.sh <herdr-app-deploy>}

work=$(mktemp -d)
trap 'chmod -R u+w "$work"; rm -rf "$work"' EXIT

fail() {
	echo "FAIL: $1" >&2
	exit 1
}

# Writes CONTENT to PATH, creating its parent folders.
put() {
	local path=$1 content=$2

	mkdir -p "${path%/*}"
	printf '%s\n' "$content" >"$path"
}

# Makes a read-only deploy tree at PATH. Its `alpha` mod's main.js and its
# desk.json hold VERSION; it has `beta` and desk.json unless WITHOUT_REMOVABLE.
make_tree() {
	local path=$1 version=$2 without_removable=${3:-}

	put "$path/mods/alpha/main.js" "alpha $version"
	put "$path/mods/alpha/mod.json" '{"name": "alpha"}'
	if [[ $version == 1 ]]; then
		put "$path/mods/alpha/extra.js" "extra"
	fi
	if [[ -z $without_removable ]]; then
		put "$path/mods/beta/mod.json" '{"name": "beta"}'
		put "$path/mods/beta/lib/util.js" "util"
		put "$path/layouts/desk.json" "{\"version\": $version}"
	fi
	mkdir -p "$path/layouts"
	chmod -R a-w "$path"
}

tree1="$work/tree1"
tree2="$work/tree2"
tree3="$work/tree3"
make_tree "$tree1" 1
make_tree "$tree2" 2
make_tree "$tree3" 2 without-removable

home="$work/home/herdr-app"
manifest="$home/dotfiles-owned.txt"
shipped="$work/shipped.txt"
printf '%s\n' mods/agents layouts/main.json >"$shipped"

put "$home/mods/agents/main.js" "shipped agents"
put "$home/mods/mine/main.js" "unowned mod"
put "$home/view.json" '{"view": true}'
put "$home/keys.error" "keys problem"
put "$home/layouts/.state/desk.json" '{"clicked": true}'
put "$home/layouts/main.json" '{"shipped": true}'
put "$home/layouts/desk.json.old-1" '{"escape": "hatch"}'
put "$work/home/x" "outside the app home"

# Prints each protected path with its inode, mtime and checksum, so any change
# to one shows as a difference.
protected_state() {
	(
		cd "$work/home"
		find herdr-app/mods/agents herdr-app/mods/mine herdr-app/view.json herdr-app/keys.error \
			herdr-app/layouts/.state herdr-app/layouts/main.json herdr-app/layouts/desk.json.old-1 x \
			-exec stat -c '%n %i %Y' {} + | sort
		find herdr-app/mods/agents herdr-app/mods/mine herdr-app/view.json herdr-app/keys.error \
			herdr-app/layouts/.state herdr-app/layouts/main.json herdr-app/layouts/desk.json.old-1 x \
			-type f -exec cksum {} + | sort
	)
}
protected_before=$(protected_state)
top_level_before=$(ls -A "$home")

# Lists the entries of FOLDER inside the app home, one per line.
entries_of() {
	ls -A "$home/$1"
}

expect_protected() {
	local name=$1

	[[ $(protected_state) == "$protected_before" ]] || fail "$name: a shipped, unowned or state entry changed"
	[[ $(ls -A "$home") == "$(printf '%s\n' "$top_level_before" dotfiles-owned.txt | sort)" ]] ||
		fail "$name: unexpected top-level entries: $(ls -A "$home")"
}

# Checks that ENTRY in the app home is a real, writable copy of TREE's.
expect_copy() {
	local name=$1 tree=$2 entry=$3

	[[ ! -L $home/$entry ]] || fail "$name: $entry is a symlink"
	[[ -w $home/$entry ]] || fail "$name: $entry is read-only"
	if [[ -d $tree/$entry ]]; then
		[[ -d $home/$entry ]] || fail "$name: $entry is not a directory"
		[[ -z $(find "$home/$entry" ! -perm -u+w) ]] || fail "$name: $entry has read-only contents"
		diff -r -x gpui-kit.d.ts -x jsconfig.json "$tree/$entry" "$home/$entry" >/dev/null ||
			fail "$name: $entry differs from the tree"
	else
		[[ -f $home/$entry ]] || fail "$name: $entry is not a regular file"
		cmp -s "$tree/$entry" "$home/$entry" || fail "$name: $entry differs from the tree"
	fi
}

expect_full_deploy() {
	local name=$1 tree=$2

	expect_copy "$name" "$tree" mods/alpha
	expect_copy "$name" "$tree" mods/beta
	expect_copy "$name" "$tree" layouts/desk.json
	[[ $(<"$manifest") == $'layouts/desk.json\nmods/alpha\nmods/beta' ]] ||
		fail "$name: manifest is: $(<"$manifest")"
	[[ $(entries_of mods) == $'agents\nalpha\nbeta\nmine' ]] || fail "$name: mods holds: $(entries_of mods)"
	[[ $(entries_of layouts) == $'.state\ndesk.json\ndesk.json.old-1\nmain.json' ]] ||
		fail "$name: layouts holds: $(entries_of layouts)"
	expect_protected "$name"
}

# Prints the inode and mtime of every deployed path.
deployed_stamps() {
	find "$home/mods/alpha" "$home/mods/beta" "$home/layouts/desk.json" -exec stat -c '%n %i %Y' {} + | sort
}

"$deploy" "$tree1" "$home" "$shipped"
expect_full_deploy "first deploy" "$tree1"

# The app writes its typings into each mod it loads; they alone must not
# count as a change.
put "$home/mods/alpha/gpui-kit.d.ts" "typings"
put "$home/mods/alpha/jsconfig.json" "{}"
stamps_before=$(deployed_stamps)
"$deploy" "$tree1" "$home" "$shipped"
[[ $(deployed_stamps) == "$stamps_before" ]] || fail "unchanged redeploy: deployed entries were touched"
expect_full_deploy "unchanged redeploy" "$tree1"

"$deploy" "$tree2" "$home" "$shipped"
expect_full_deploy "changed mod and layout" "$tree2"
[[ $(<"$home/mods/alpha/main.js") == "alpha 2" ]] || fail "changed mod: main.js is not the new one"
[[ ! -e $home/mods/alpha/extra.js ]] || fail "changed mod: a file the tree dropped remains"
[[ $(<"$home/layouts/desk.json") == '{"version": 2}' ]] || fail "changed layout: desk.json is not the new one"

put "$home/mods/beta/lib/util.js" "edited in place"
put "$home/mods/beta/lib/added.js" "added in place"
put "$home/layouts/desk.json" '{"rewritten": "by the app"}'
"$deploy" "$tree2" "$home" "$shipped"
expect_full_deploy "drifted targets" "$tree2"

mkdir -p "$home/mods/.alpha.dotfiles-new/sub"
chmod -R a-w "$home/mods/.alpha.dotfiles-new"
put "$home/layouts/.desk.json.dotfiles-new" "half written"
"$deploy" "$tree2" "$home" "$shipped"
expect_full_deploy "leftover staging copies" "$tree2"

# The link targets hold the tree's content, so only the symlinks themselves
# make the entries need a deploy.
outside="$work/outside"
mkdir -p "$outside"
cp -R "$tree2/mods/beta" "$outside/beta"
cp "$tree2/layouts/desk.json" "$outside/desk.json"
chmod -R a-w "$outside"
outside_before=$(find "$outside" -exec stat -c '%n %i %Y' {} + | sort)
rm -rf "$home/mods/beta" "$home/layouts/desk.json"
ln -s "$outside/beta" "$home/mods/beta"
ln -s "$outside/desk.json" "$home/layouts/desk.json"
"$deploy" "$tree2" "$home" "$shipped"
expect_full_deploy "leftover symlinks" "$tree2"
[[ $(find "$outside" -exec stat -c '%n %i %Y' {} + | sort) == "$outside_before" ]] ||
	fail "leftover symlinks: a link target changed"

# The escape hatch renames the shown layout aside; the next deploy restores it.
mv "$home/layouts/desk.json" "$home/layouts/desk.json.old-2"
"$deploy" "$tree2" "$home" "$shipped"
[[ $(<"$home/layouts/desk.json.old-2") == '{"version": 2}' ]] || fail "escape hatch: the renamed layout changed"
rm "$home/layouts/desk.json.old-2"
expect_full_deploy "escape hatch" "$tree2"

printf '%s\n' ../x /abs mods/agents layouts/.state layouts/main.json mods/../view.json "mods/" >>"$manifest"
mkdir -p "$home/mods/.beta.dotfiles-new"
"$deploy" "$tree3" "$home" "$shipped"
expect_copy "removed entries" "$tree3" mods/alpha
[[ $(<"$manifest") == "mods/alpha" ]] || fail "removed entries: manifest is: $(<"$manifest")"
[[ $(entries_of mods) == $'agents\nalpha\nmine' ]] || fail "removed entries: mods holds: $(entries_of mods)"
[[ $(entries_of layouts) == $'.state\ndesk.json.old-1\nmain.json' ]] ||
	fail "removed entries: layouts holds: $(entries_of layouts)"
expect_protected "removed entries"

echo "deploy fixtures passed"
