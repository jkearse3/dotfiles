# shellcheck shell=bash
# Makes a Ghostty theme file Rex's dark theme, through the running Rex app.
#
# Usage: rex-apply-theme REX_CLI THEME_FILE
#
# Rex imports a theme file as a custom theme named after the file and keeps
# it, with a generated ID, in its `Workspace.customThemes` preference. So this
# imports the file only when no custom theme has its name, which also makes it
# the dark theme, and otherwise points the dark theme at that custom theme.
# Rex performs both through app actions, which need the app running with
# Remote Control on; when they fail, this warns and exits 0 so a Home Manager
# switch still succeeds.

rex_cli=$1
theme_file=$2
theme_name=$(basename "$theme_file")
preferences="$HOME/Library/Preferences/com.superlogical.rex.plist"

skip() {
	echo "rex theme: $1; set it with Settings > Theme > Import ($theme_file)." >&2
	exit 0
}

rex_app() {
	"$rex_cli" --autostart=false --timeout 5s "$@" >/dev/null 2>&1
}

[ -x "$rex_cli" ] || skip "Rex is not installed"

theme_id=$(
	/usr/libexec/PlistBuddy -c 'Print :Workspace.customThemes' "$preferences" 2>/dev/null |
		jq -r --arg name "$theme_name" 'first(.[] | select(.name == $name) | .id) // empty' 2>/dev/null
) || theme_id=""

if [ -z "$theme_id" ]; then
	rex_app "do" client.theme.import path="$theme_file" ||
		skip "could not import $theme_name (is Rex running with Remote Control on?)"
	exit 0
fi

current_id=$(/usr/bin/defaults read com.superlogical.rex Workspace.darkThemeID 2>/dev/null) || current_id=""
[ "$current_id" = "$theme_id" ] && exit 0

rex_app "do" client.setting.themes.dark.palette value="$theme_id" ||
	skip "could not select $theme_name (is Rex running with Remote Control on?)"
