#!/usr/bin/env bash

# Merge Nix-declared pi settings into the file pi owns at runtime.
#
# Pi reads settings from ~/.pi/agent/settings.json and no layer above it: there
# is no --settings flag and no environment override for settings content. It
# also rewrites that file whenever the user changes a theme, provider, model,
# thinking level, or TUI mode in the app, and a read-only store symlink in its
# place makes `pi install` report success while silently discarding the write.
# So the only safe delivery is to merge into the writable file at activation.
#
# Two buckets with opposite directions:
#
#   Seed keys are fallback defaults for values absent from the live file. They
#   merge as `seed * live`, so a value pi wrote always wins and is never
#   re-asserted. A key retired from the seed therefore stays in the live file; a
#   merge cannot delete.
#
#   `packages` is reconciled instead, because pi replaces arrays wholesale on
#   merge and a Nix-declared array would discard everything `pi install` added.
#   Nix owns exactly the identities it placed in the previous generation: those
#   are dropped when they leave the Nix list and replaced when the Nix list
#   changes them, and everything else is left alone.
#
# usage: pi-settings-merge <settings> <seed-json> <packages-json> [<previous-packages-json>]

set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
	echo "usage: pi-settings-merge <settings> <seed-json> <packages-json> [<previous-packages-json>]" >&2
	exit 2
fi

settings=$1
seed_file=$2
packages_file=$3
previous_file=${4-}

agent_dir=$(dirname -- "$settings")
mkdir -p -- "$agent_dir"

# A first activation, or one following a generation built before packages were
# recorded, has no previous Nix set. Treat it as empty rather than failing:
# nothing is then attributed to Nix, so nothing is removed.
previous='[]'
if [[ -n $previous_file && -f $previous_file ]]; then
	previous=$(cat -- "$previous_file")
fi

# `cat`, not `cp`: the seed is a store file and would carry 0444 across.
if [[ ! -f $settings ]]; then
	printf '{}\n' >"$settings"
fi

# Pi's own identity rules. It matches an npm source by bare package name and a
# git source by host and path, then rewrites the stored entry in place when a
# re-install resolves to the same one, so comparing whole strings would make a
# version bump or an ssh-versus-https spelling look like a second package. A
# local path is compared by its resolved location because pi rewrites an
# installed local path to be relative to the agent directory.
# shellcheck disable=SC2016  # $live, $seed, and friends are jq variables.
merge_program='
def trimmed: sub("^\\s+"; "") | sub("\\s+$"; "");

def source_string:
  (if type == "object" then (.source // "") else . end)
  | tostring
  | trimmed;

def is_remote:
  startswith("npm:")
  or startswith("git:")
  or startswith("github:")
  or startswith("http:")
  or startswith("https:")
  or startswith("ssh:");

# Lexical resolution, matching node path.resolve. Deliberately not realpath:
# pi does not follow symlinks when it stores a path either.
def resolve_local($base):
  (if . == "~" then $home
   elif startswith("~/") then $home + .[1:]
   else . end)
  | (if startswith("/") then . else $base + "/" + . end)
  | split("/")
  | reduce .[] as $segment ([];
      if $segment == "" or $segment == "." then .
      elif $segment == ".." then (if length > 0 then .[0:length - 1] else . end)
      else . + [$segment]
      end)
  | "/" + join("/");

# Mirrors pi parseNpmSpec: a leading @ belongs to the scope, so the version
# separator is the first @ after position 0.
def npm_identity:
  ltrimstr("npm:")
  | (capture("^(?<name>@?[^@]+(?:/[^@]+)?)(?:@.+)?$") // { name: . })
  | "npm:" + .name;

# Reduces every spelling pi accepts to host and path, dropping the git: prefix,
# a .git suffix, and the hosted shorthands hostedGitInfo expands. Pi splits a
# ref on either # or the first @ left in the path, so both go.
#
# The scheme decides how a colon reads, which is why this branches before
# stripping one, mirroring parseGenericGitUrl. In a URL the colon introduces a
# port, and pi reads host and path from new URL(), which excludes it. In an
# scp-style source the colon separates host from path. Deciding after the
# scheme were gone would leave a port and a numeric first path segment
# indistinguishable.
#
# The URL host alternates a bracketed literal ahead of the ordinary class so an
# IPv6 address survives its own colons, and the port match must be followed by a
# path or the end of the string, so a bracketed host carrying no port is left
# whole rather than cut at its first colon.
def git_identity:
  ltrimstr("git:")
  | split("#")[0]
  | sub("^github:"; "github.com/")
  | sub("^gitlab:"; "gitlab.com/")
  | sub("^bitbucket:"; "bitbucket.org/")
  | if test("^[a-zA-Z][a-zA-Z0-9+.-]*://") then
      sub("^[a-zA-Z][a-zA-Z0-9+.-]*://"; "")
      | sub("^[^/@]+@"; "")
      | sub("^(?<host>\\[[^\\]]*\\]|[^/:]+):[0-9]*(?=/|$)"; "\(.host)")
    else
      sub("^[^/@]+@"; "")
      | sub(":"; "/")
    end
  | split("@")[0]
  | sub("\\.git$"; "")
  | sub("/+$"; "")
  | ascii_downcase
  | "git:" + .;

def identity($base):
  source_string
  | if startswith("npm:") then npm_identity
    elif is_remote then git_identity
    else "local:" + resolve_local($base)
    end;

($live[0] // {}) as $liveSettings
| ($seed[0] // {}) as $seedSettings
| ($declared[0] // []) as $declaredPackages
| ($previous // []) as $previousPackages
# A freshly seeded file has no packages key, and pi writes null before it writes
# its first entry. Either would abort activation on the array operations below.
| ($liveSettings.packages // []) as $livePackages
| (reduce $previousPackages[] as $entry ({}; .[$entry | identity($base)] = $entry))
  as $previousById
| (reduce $declaredPackages[] as $entry ({}; .[$entry | identity($base)] = $entry))
  as $declaredById
# Nix owns identities, not slots: a live file holding two entries for one
# Nix-owned package collapses to one, while duplicates Nix never placed are left
# exactly as they are.
| (reduce $livePackages[] as $entry ({ emitted: {}, out: [] };
     ($entry | identity($base)) as $id
     | if ($previousById | has($id) | not) then .out += [$entry]
       elif ($declaredById | has($id) | not) then .
       elif .emitted[$id] then .
       else
         .emitted[$id] = true
         # Take the declared form only when Nix itself changed it, so an entry
         # pi normalized or promoted to object form keeps the shape pi gave it.
         | .out += [if $declaredById[$id] == $previousById[$id]
                    then $entry
                    else $declaredById[$id]
                    end]
       end)
   | .out) as $kept
| [$kept[] | identity($base)] as $keptIds
| ($kept + [$declaredPackages[]
            | select(identity($base) as $id | ($keptIds | index($id)) == null)])
  as $mergedPackages
| ($seedSettings * $liveSettings)
| if ($mergedPackages | length) > 0 or ($liveSettings | has("packages"))
  then .packages = $mergedPackages
  else .
  end
'

tmp=$(mktemp)
trap 'rm -f -- "$tmp"' EXIT

jq -n \
	--arg base "$agent_dir" \
	--arg home "$HOME" \
	--slurpfile live "$settings" \
	--slurpfile seed "$seed_file" \
	--slurpfile declared "$packages_file" \
	--argjson previous "$previous" \
	"$merge_program" >"$tmp"

# mktemp creates 0600, which is the mode pi expects on a file holding provider
# configuration next to its auth store.
mv -- "$tmp" "$settings"
trap - EXIT
