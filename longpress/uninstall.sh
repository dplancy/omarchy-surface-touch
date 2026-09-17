#!/bin/bash
# Remove the long-press plugin installed by longpress/install.sh.
# Usage: ./longpress/uninstall.sh
set -uo pipefail

LIB_DIR="$HOME/.local/lib/omarchy-surface-longpress"
SO="$LIB_DIR/longpress.so"
HOOK="$HOME/.config/omarchy/hooks/post-update.d/omarchy-surface-longpress"
HYPR_FILE="$HOME/.config/hypr/surface-longpress.lua"
HYPR_MAIN="$HOME/.config/hypr/hyprland.lua"
HYPR_REQUIRE='require("hypr.surface-longpress") -- omarchy-surface-touch long press'

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

echo "== unload from the running Hyprland"
hyprctl plugin unload "$SO" >/dev/null 2>&1

echo "== Hyprland rule"
remove_line "$HYPR_REQUIRE" "$HYPR_MAIN"
rm -f "$HYPR_FILE"

echo "== update hook"
rm -f "$HOOK"

echo "== plugin"
rm -rf "$LIB_DIR"

echo
echo "done. Long press goes back to doing nothing outside apps that handle it themselves."
