# shellcheck shell=bash
# Applies the repository's Hex settings and vocabulary to the installed Hex.
#
# Usage: hex-apply-settings HEX_CLI SETTINGS_JSON VOCABULARY_JSON
#
# SETTINGS_JSON maps `hex settings list` keys to values. `hex settings apply`
# writes those keys, through the running app or straight into settings.json
# when Hex is stopped, and leaves every other setting as Hex last saved it.
#
# VOCABULARY_JSON is a list of {"term", "sounds_like"} entries. Hex changes
# vocabulary only through the running app, and `hex vocabulary add` only adds
# a term or spellings it lacks, so terms or spellings removed from the file
# stay in Hex until removed there.
#
# Every failure warns and exits 0, so a Home Manager switch still succeeds.

hex_cli=$1
settings_file=$2
vocabulary_file=$3

warn() {
	echo "hex: $1" >&2
}

# Matches the CLI's documented exit code for "Hex isn't running".
readonly hex_not_running=3

if [ ! -x "$hex_cli" ]; then
	warn "Hex is not installed at $hex_cli; its settings were not applied"
	exit 0
fi

if ! "$hex_cli" settings apply "$settings_file" >/dev/null; then
	warn "could not apply the settings in $settings_file"
fi

mapfile -t vocabulary_entries < <(jq -c '.[]' "$vocabulary_file")
for entry in "${vocabulary_entries[@]}"; do
	term=$(jq -r '.term' <<<"$entry")
	spellings=$(jq -r '.sounds_like | join(",")' <<<"$entry")
	add_command=(vocabulary add "$term")
	if [ -n "$spellings" ]; then
		add_command+=(--sounds-like "$spellings")
	fi

	add_status=0
	"$hex_cli" "${add_command[@]}" >/dev/null 2>&1 || add_status=$?
	if [ "$add_status" -eq "$hex_not_running" ]; then
		warn "Hex is not running, so its vocabulary was not updated; switch again with Hex open"
		exit 0
	elif [ "$add_status" -ne 0 ]; then
		warn "could not add \"$term\" to the vocabulary"
	fi
done
