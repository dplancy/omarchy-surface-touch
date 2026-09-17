#!/bin/bash
# Remove the on-screen keyboard installed by osk/install.sh.
# Usage: ./osk/uninstall.sh
set -uo pipefail

LIB_DIR="$HOME/.local/lib/omarchy-surface-osk"
BIN_LINK="$HOME/.local/bin/omarchy-surface-osk"
UNIT="$HOME/.config/systemd/user/omarchy-surface-osk.service"
PLUGIN_ID=surface-touch.osk
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
HYPR_FILE="$HOME/.config/hypr/surface-osk.lua"
HYPR_MAIN="$HOME/.config/hypr/hyprland.lua"
HYPR_REQUIRE='require("hypr.surface-osk") -- omarchy-surface-touch on-screen keyboard'
CONFIG_DIR="$HOME/.config/omarchy-surface-osk"
CHROMIUM_FLAGS="$HOME/.config/chromium-flags.conf"

((EUID != 0)) || {
	echo "ERROR: run this script as your user, not with sudo"
	exit 1
}

remove_line() {
	[[ -f $2 ]] || return 0
	local tmp
	tmp=$(mktemp) && grep -vxF -- "$1" "$2" >"$tmp"
	cat "$tmp" >"$2" && rm -f "$tmp"
}

echo "== service (stopping it also restores fcitx5's normal interface)"
systemctl --user disable --now omarchy-surface-osk.service 2>/dev/null
rm -f "$UNIT"
systemctl --user daemon-reload

echo "== shell plugin"
omarchy plugin disable "$PLUGIN_ID" 2>/dev/null
rm -rf "$PLUGIN_DIR"
omarchy-shell -q shell rescanPlugins

echo "== Hyprland rule"
remove_line "$HYPR_REQUIRE" "$HYPR_MAIN"
rm -f "$HYPR_FILE"
hyprctl reload config-only >/dev/null 2>&1

echo "== Chromium flags added by the installer"
if [[ -f $CONFIG_DIR/added-chromium-flags ]]; then
	while IFS= read -r flag; do
		[[ -n $flag ]] && remove_line "$flag" "$CHROMIUM_FLAGS"
	done <"$CONFIG_DIR/added-chromium-flags"
	rm -f "$CONFIG_DIR/added-chromium-flags"
fi

echo "== programs"
rm -rf "$LIB_DIR"
rm -f "$BIN_LINK"

echo
echo "done. Your settings are kept in $CONFIG_DIR/config.json (delete the folder to remove them)."
