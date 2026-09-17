#!/bin/bash
# Remove the automatic screen rotation installed by rotate/install.sh.
# Usage: ./rotate/uninstall.sh
set -uo pipefail

LIB_DIR="$HOME/.local/lib/omarchy-surface-rotate"
BIN_LINK="$HOME/.local/bin/omarchy-surface-rotate"
UNIT="$HOME/.config/systemd/user/omarchy-surface-rotate.service"
PLUGIN_ID=surface-touch.rotate
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
CONFIG_DIR="$HOME/.config/omarchy-surface-rotate"
HYPR_FILE="$HOME/.config/hypr/surface-rotate.lua"
HYPR_MAIN="$HOME/.config/hypr/hyprland.lua"
HYPR_REQUIRE='require("hypr.surface-rotate") -- omarchy-surface-touch screen rotation'

remove_line() {
	[[ -f $2 ]] || return 0
	local tmp
	tmp=$(mktemp) && grep -vxF -- "$1" "$2" >"$tmp"
	cat "$tmp" >"$2" && rm -f "$tmp"
}

((EUID != 0)) || {
	echo "ERROR: run this script as your user, not with sudo"
	exit 1
}

echo "== service"
systemctl --user disable --now omarchy-surface-rotate.service 2>/dev/null
rm -f "$UNIT"
systemctl --user daemon-reload

echo "== shell plugin"
omarchy plugin disable "$PLUGIN_ID" 2>/dev/null
rm -rf "$PLUGIN_DIR"
omarchy-shell -q shell rescanPlugins

echo "== screen back to landscape"
remove_line "$HYPR_REQUIRE" "$HYPR_MAIN"
rm -f "$HYPR_FILE"
hyprctl reload config-only >/dev/null 2>&1

echo "== programs"
rm -rf "$LIB_DIR"
rm -f "$BIN_LINK"

echo
echo "done. Your settings are kept in $CONFIG_DIR/config.json (delete the folder to remove them)."
