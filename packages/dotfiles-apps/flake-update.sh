# shellcheck shell=bash
# `private_override` is set by `main` in `dotfiles-apps.sh`.
# shellcheck disable=SC2154

# The flake-update command of `dotfiles-apps.sh`, which `package.nix` places
# before it in the same script. It updates the flake inputs and package pins in
# a jj change of their own, checks that every blueprint still evaluates, that
# `nix flake check` passes, and that the selected blueprint's Home Manager and
# nix-darwin configurations build, then commits the change with a description
# listing what moved. A failed check leaves the update in `@`, and the next run
# resumes it: it reruns the checks without updating again, so a fix made in `@`
# lands in the same change; a fix to files other than the dependency pins
# needs an explanation in the description of `@`. `jj` and `commit-message`
# come from the user's PATH and the script's runtime inputs respectively.

# The subject of every dependency update. A non-empty `@` with this subject is
# an update a previous run left for a fix, which the next run resumes.
dependency_update_subject="build(nix): update dependencies"

# Updates, checks, describes, and commits the dependencies of the blueprint
# `blueprint_id`, whose Home Manager and nix-darwin configurations are
# `home_configuration_name` and `darwin_configuration_name`. Commits nothing
# when no dependency changed. Exits 1 when updating fails, restoring `@` to its
# parent; when `@` holds a fix whose description lacks an explanation; and when
# a check fails, `@` changes while the checks run, or jj
# cannot describe or commit the update, leaving the update in `@` with
# instructions to resume or discard it.
flake_update() {
	local blueprint_id=$1
	local home_configuration_name=$2
	local darwin_configuration_name=$3

	if is_dependency_update_in_progress; then
		echo "Resuming the dependency update in @; run 'jj abandon @' first to start over"
	else
		start_dependency_update
		if [[ "$(jj log -r @ --no-graph -T empty)" == true ]]; then
			echo "Dependencies unchanged; nothing to commit"
			return
		fi
		if ! jj describe -m "$dependency_update_subject"; then
			echo "error: describing the update in @ failed, so the next run cannot resume it; run 'jj describe -m \"$dependency_update_subject\"' and rerun 'nix run .#flake-update', or run 'jj abandon @' to discard the update" >&2
			exit 1
		fi
	fi

	require_fix_explanation

	local checked_commit
	checked_commit="$(jj log -r @ --no-graph -T commit_id)"

	local home_attribute=".#homeConfigurations.\"$home_configuration_name\".activationPackage"
	local darwin_attribute=".#darwinConfigurations.\"$darwin_configuration_name\".system"
	run_update_check "evaluating every blueprint" \
		build --no-link --accept-flake-config "${private_override[@]}" .#eval-blueprints
	run_update_check "nix flake check" \
		flake check --accept-flake-config "${private_override[@]}"
	run_update_check "building home configuration '$home_configuration_name'" \
		build --no-link --accept-flake-config "${private_override[@]}" "$home_attribute"
	run_update_check "building system configuration '$darwin_configuration_name'" \
		build --no-link --accept-flake-config "${private_override[@]}" "$darwin_attribute"

	if [[ -n "$(jj diff --from "$checked_commit" --to @ --summary)" ]]; then
		fail_dependency_update "files in @ changed while the checks ran, so the checks did not cover them"
	fi

	local description
	description="$(describe_dependency_update "$blueprint_id" "$home_attribute" "$darwin_attribute")" || exit 1
	echo "==> Committing the dependency update"
	if ! jj commit -m "$description"; then
		fail_dependency_update "committing the update failed"
	fi
	printf '\n%s\n\n' "$description"
	echo "==> Committed the dependency update as $(jj log -r @- --no-graph -T 'change_id.short()')"
}

# Succeeds when `@` holds a dependency update that a previous run left
# uncommitted: it has changes and its subject is the dependency update subject.
is_dependency_update_in_progress() {
	local working_copy_state
	working_copy_state="$(jj log -r @ --no-graph -T 'if(empty, "empty", description.first_line())')"
	[[ $working_copy_state == "$dependency_update_subject" ]]
}

# Moves to a fresh change, unless `@` is already empty and undescribed, and
# updates the flake inputs and package pins there. When either update fails,
# restores `@` to its parent, so no partial update remains, and exits 1.
#
# The inputs update without DOTFILES_PRIVATE_LOCAL's override, because
# `nix flake update` writes an overridden input into flake.lock: the lock keeps
# recording dotfiles-private's remote revision, and only the checks build
# against the local checkout.
start_dependency_update() {
	if [[ "$(jj log -r @ --no-graph -T 'empty && !description')" != true ]]; then
		jj new
	fi

	echo "==> Updating flake inputs and package pins"
	if ! nix flake update --accept-flake-config || ! package_update ""; then
		jj restore
		echo "error: updating dependencies failed; @ is restored to its parent, so rerun 'nix run .#flake-update' once the cause is fixed" >&2
		exit 1
	fi
}

# Returns when `@` changes only dependency files, or when its description
# explains the other changes below the subject. Otherwise the update needed a
# fix whose reason the generated lists cannot give, so it names the fix files
# and how to add the explanation, and exits 1 before any check runs.
require_fix_explanation() {
	local fix_files
	fix_files="$(list_fix_files)"
	[[ -n $fix_files ]] || return 0

	local explanation
	explanation="$(jj log -r @ --no-graph -T description | strip_generated_description)"
	[[ -z $explanation ]] || return 0

	echo "error: the dependency update in @ also changes files beyond the dependency pins:" >&2
	echo "  ${fix_files//$'\n'/$'\n'  }" >&2
	cat >&2 <<EOF
Its description needs an explanation of that fix, which the generated lists
cannot give: why the update needed it and what it changes. Write it below the
subject with 'jj describe', then run 'nix run .#flake-update' again.
EOF
	exit 1
}

# Prints the files `@` changes other than dependency files: flake.lock and the
# files of each package that has a `packages/<name>/update.sh` updater.
list_fix_files() {
	local changed_file
	while IFS= read -r changed_file; do
		[[ $changed_file != flake.lock ]] || continue
		if [[ $changed_file == packages/*/* ]]; then
			local package_path=${changed_file#packages/}
			[[ ! -x packages/${package_path%%/*}/update.sh ]] || continue
		fi
		echo "$changed_file"
	done < <(jj diff -r @ --name-only)
}

# Runs `nix` with the remaining arguments as one check of the dependency update
# in `@`, after announcing `check_name`. When it fails, reports the failed check
# and how to resume, and exits 1.
run_update_check() {
	local check_name=$1
	shift

	echo "==> Checking: $check_name"
	if ! nix "$@"; then
		fail_dependency_update "$check_name failed"
	fi
}

# Reports `reason` with the state of the update left in `@` and the commands
# that resume or discard it, then exits 1.
fail_dependency_update() {
	local reason=$1

	cat >&2 <<EOF
error: $reason.
The dependency update stays uncommitted in @. Fix the failure there and run
'nix run .#flake-update' again: it reruns the checks without updating again
and commits the update with your fix. Add any explanation of the fix to the
description of @ ('jj describe'); the next run keeps it. To discard the update
instead, run 'jj abandon @'.
EOF
	exit 1
}

# Prints the formatted, validated description of the dependency update in `@`:
# the dependency update subject, any explanation already written in the
# description of `@` after its subject, and generated lists of the flake
# inputs, package pins, and package versions of blueprint `blueprint_id` that
# changed. `home_attribute` and `darwin_attribute` are the flake attributes of
# the blueprint's configurations. Exits 1 when the description fails
# validation.
describe_dependency_update() {
	local blueprint_id=$1
	local home_attribute=$2
	local darwin_attribute=$3

	local explanation
	explanation="$(jj log -r @ --no-graph -T description | strip_generated_description)"

	local generated_sections=(
		"$(describe_input_changes)"
		"$(describe_pin_changes)"
		"$(describe_package_version_changes "$blueprint_id" "$home_attribute" "$darwin_attribute")"
	)

	local description=$dependency_update_subject section
	for section in "$explanation" "${generated_sections[@]}"; do
		if [[ -n $section ]]; then
			description+=$'\n\n'"$section"
		fi
	done

	description="$(printf '%s\n' "$description" | commit-message format)"
	if ! printf '%s\n' "$description" | commit-message validate --require-body --conventional >&2; then
		fail_dependency_update "the generated description failed validation"
	fi
	printf '%s\n' "$description"
}

# Reads a dependency update description on standard input and prints the
# explanation written after its subject, without the generated lists, which
# start at the first of their headings, and without leading blank lines.
# Callers capture it with command substitution, which drops trailing ones.
strip_generated_description() {
	sed -E '1d; /^(Flake inputs|Package pins|Package versions in .*):$/,$d' | sed '/./,$!d'
}

# Prints a "Flake inputs:" list of every locked input whose revision changed
# between flake.lock in `@-` and in `@`, named by its path from the root inputs
# (`llm-agents/nixpkgs`), with the old and new short revisions and commit
# dates. Prints nothing when no input changed.
describe_input_changes() {
	jq -rn \
		--argjson old "$(jj file show -r @- flake.lock)" \
		--argjson new "$(jj file show -r @ flake.lock)" '
		# Maps the path of each input reachable from the root inputs, such as
		# `llm-agents/nixpkgs`, to its locked source. A node reachable along
		# several paths keeps its shortest, and `follows` entries, which are
		# arrays, are skipped because they point at nodes named elsewhere.
		def locked_inputs:
			. as $lock
			| def input_paths($key; $path):
				($lock.nodes[$key].inputs // {}) | to_entries[]
				| select(.value | type == "string")
				| { path: ($path + [.key]), key: .value }
				| ., input_paths(.key; .path);
			[input_paths($lock.root; [])]
			| group_by(.key)
			| map(min_by(.path | length) | { key: (.path | join("/")), value: $lock.nodes[.key].locked })
			| from_entries;

		def locked_summary:
			if . == null then "none"
			else
				(.rev // .narHash // "unknown")[0:7]
				+ (if .lastModified then " (\(.lastModified | strftime("%Y-%m-%d")))" else "" end)
			end;

		($old | locked_inputs) as $before
		| ($new | locked_inputs) as $after
		| [ ($before + $after | keys)[]
			| select($before[.] != $after[.])
			| "- \(.): \($before[.] | locked_summary) -> \($after[.] | locked_summary)" ]
		| if length > 0 then "Flake inputs:\n" + join("\n") else empty end'
}

# Prints a "Package pins:" list of every `packages/*/package.nix` whose
# `version` differs between `@-` and `@`, with the old and new versions. Prints
# nothing when no pinned version changed.
describe_pin_changes() {
	local changes=() package_file
	while IFS= read -r package_file; do
		[[ $package_file == packages/*/package.nix ]] || continue

		local old_version new_version
		old_version="$(jj file show -r @- "$package_file" 2>/dev/null | pinned_version)"
		new_version="$(jj file show -r @ "$package_file" 2>/dev/null | pinned_version)"
		if [[ $old_version != "$new_version" ]]; then
			local package_name=${package_file#packages/}
			changes+=("- ${package_name%/package.nix}: ${old_version:-none} -> ${new_version:-none}")
		fi
	done < <(jj diff -r @ --name-only)

	if [[ ${#changes[@]} -gt 0 ]]; then
		printf 'Package pins:\n'
		printf '%s\n' "${changes[@]}"
	fi
}

# Reads a package.nix on standard input and prints the first `version = "...";`
# value, or nothing when it has none.
pinned_version() {
	sed -nE 's/^[[:space:]]*version = "([^"]+)";$/\1/p' | head -n 1
}

# Prints a "Package versions in the <blueprint_id> blueprint (<system>):" list
# of the package versions that differ between the configurations built from
# `@-` and from `@`. It compares the whole closures of what the blueprint
# installs through `home.packages` and `environment.systemPackages`, so it also
# reports packages behind unversioned wrappers, such as an agent CLI, and their
# dependencies. `home_attribute` and `darwin_attribute` are the configurations'
# flake attributes relative to `.`. Prints nothing when no version changed, and
# only a warning when `@-`'s configurations cannot be built, since the list is
# informational.
describe_package_version_changes() {
	local blueprint_id=$1
	local home_attribute=$2
	local darwin_attribute=$3

	local parent_flake
	parent_flake="git+file://$PWD?rev=$(jj log -r @- --no-graph -T commit_id)"

	echo "==> Building the configurations of @- to compare package versions" >&2
	local old_packages new_packages
	if ! old_packages="$(installed_closure "$parent_flake${home_attribute#.}" "$parent_flake${darwin_attribute#.}")"; then
		echo "warning: could not build the configurations of @-, so the description omits package versions" >&2
		return 0
	fi
	new_packages="$(installed_closure "$home_attribute" "$darwin_attribute")"

	local platform platform_targets
	platform="$(blueprint_output platform "$blueprint_id")"
	platform_targets="$(blueprint_output platform-targets "$blueprint_id")"

	jq -rn \
		--arg old "$old_packages" \
		--arg new "$new_packages" \
		--arg blueprint "$blueprint_id" \
		--arg platform "$platform" \
		--arg targets "$platform_targets" '
		($targets | split("\n") | map(select(. != ""))) as $own_targets

		# Removes `suffix` from the end of the string, when it ends with it.
		| def drop_suffix($suffix):
			if endswith($suffix) then .[:length - ($suffix | length)] else . end;

		# Maps package names to their sorted versions, from store path names
		# split as `builtins.parseDrvName` splits them: the version starts at
		# the first `-` followed by a digit. Store paths without a version,
		# such as wrappers and configuration files, carry no version to
		# compare and are skipped. An output or completions suffix, as in
		# `curl-8.23.0-bin` or `fzf-0.75.0-fish-completions`, and the
		# blueprint'"'"'s own target triple, as in
		# `cargo-1.99.1-aarch64-apple-darwin`, would otherwise read as part of
		# the version; the list heading names the platform instead. A
		# different target triple stays in the version, so a cross target
		# reports its own changes.
		def versions:
			split("\n")
			| map(
				select(. != "")
				| sub("^/nix/store/[^-]+-"; "")
				| sub("-(bin|man|doc|devdoc|info|dev|lib|out|fish-completions)$"; "")
				| reduce $own_targets[] as $target (.; drop_suffix("-" + $target))
				| capture("^(?<name>.+?)-(?<version>[0-9].*)$")?)
			| group_by(.name)
			| map({ key: .[0].name, value: (map(.version) | unique) })
			| from_entries;

		# Sorts versions by their numeric parts, so 1.100.0 follows 1.99.1.
		def version_sorted:
			sort_by([scan("[0-9]+|[^0-9.]+") | tonumber? // .]);

		# Lists each package whose set of versions changed, with only the
		# versions it lost and gained, since a closure can hold several
		# versions of one package at once. Packages that made the same change,
		# such as the components of one toolchain, share a line.
		($old | versions) as $before
		| ($new | versions) as $after
		| [ ($before + $after | keys)[] as $name
			| ($before[$name] // []) as $old_versions
			| ($after[$name] // []) as $new_versions
			| {
				name: $name,
				removed: ($old_versions - $new_versions | version_sorted),
				added: ($new_versions - $old_versions | version_sorted)
			}
			| select(.removed != [] or .added != []) ]
		| group_by([.removed, .added])
		| sort_by(.[0].name)
		| map(
			(map(.name) | join(", ")) as $names
			| .[0]
			| if .removed == [] then "- \($names): added \(.added | join(", "))"
			elif .added == [] then "- \($names): removed \(.removed | join(", "))"
			else "- \($names): \(.removed | join(", ")) -> \(.added | join(", "))" end)
		| if length > 0
			then "Package versions in the \($blueprint) blueprint (\($platform)):\n" + join("\n")
			else empty end'
}

# Builds the Home Manager activation package `home_installable` and nix-darwin
# system `darwin_installable` and prints the store paths in the closures of the
# packages they install: the generation's `home-path` and the system's `sw`.
# Fails when either build fails.
installed_closure() {
	local home_installable=$1
	local darwin_installable=$2

	local home_generation darwin_system
	home_generation="$(nix build --no-link --print-out-paths --accept-flake-config "${private_override[@]}" "$home_installable")" || return
	darwin_system="$(nix build --no-link --print-out-paths --accept-flake-config "${private_override[@]}" "$darwin_installable")" || return

	nix-store --query --requisites "$(readlink -f "$home_generation/home-path")" "$(readlink -f "$darwin_system/sw")"
}
